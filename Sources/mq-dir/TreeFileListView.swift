import AppKit
import SwiftUI

/// VS Code Explorer-style tree view of the focused tab's folder.
///
/// Renders the root folder at depth 0 and lazily descends only into the
/// subfolders the user has explicitly expanded (tracked on the VM as
/// `expandedPaths`). Folder-first ordering inside each level — files
/// follow — matches what VS Code does and stops a deep tree from being
/// drowned in loose files at every level.
struct TreeFileListView: View {
    @ObservedObject var viewModel: FolderBrowserViewModel
    /// App-level `.environmentObject(workspace)` so the tree-row drag
    /// source can read the "normalise Hangul on drag out" preference,
    /// matching the list view's `BrowserPaneView` path.
    @EnvironmentObject private var workspace: WorkspaceManager
    let isFocused: Bool
    let onFocus: () -> Void

    @FocusState private var treeFocused: Bool

    private var normalizeHangulOnDragOut: Bool {
        workspace.workspace.settings.normalizeHangulOnDragOut
    }

    var body: some View {
        // ScrollViewReader provides a proxy so arrow-key nav can keep the
        // moved-to row visible. Each treeRow stamps `.id(entry.id)` so the
        // proxy can find rows by their FileEntry.ID. Mirrors what the list
        // mode does in `BrowserPaneView.fileList`.
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let root = viewModel.folderURL,
                       let rootEntries = viewModel.treeChildren[root.path] ?? entriesForRoot()
                    {
                        ForEach(FileEntry.treeOrdered(rootEntries)) { entry in
                            treeRow(entry, depth: 0)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 2)
            }
            .scrollPosition(id: Binding(get: { viewModel.treeScrollID }, set: { value in
                if !viewModel.isLoading && viewModel.loadingTreePaths.isEmpty && viewModel.treeScrollID != value { viewModel.treeScrollID = value }
            }), anchor: .top)
            .focusable()
            .focused($treeFocused)
            .onAppear {
                if isFocused { treeFocused = true }
            }
            .onChange(of: isFocused) { _, newValue in
                if newValue { treeFocused = true }
            }
            // "Reveal in Tree" queues a row ID on the VM; scroll it into view
            // once the expanded ancestors have rendered, then clear the
            // signal so a later identical reveal still fires. Deferred one
            // runloop turn so the freshly-inserted `expandedPaths` rows have
            // materialised in the LazyVStack before the proxy looks for them.
            .onChange(of: viewModel.pendingRevealTarget) { _, target in
                guard let target else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(target, anchor: .center)
                    viewModel.pendingRevealTarget = nil
                }
            }
            // Root cache freshness is owned by the VM (`entries` didSet +
            // `refreshTreeChildren`), so this view no longer mirrors entries
            // into `treeChildren[root]`. The `entriesForRoot()` fallback in
            // the body covers the one frame before the first `entries`
            // assignment lands.
            // KeyPress carries the modifier state captured at the press
            // moment, where `NSEvent.modifierFlags` only reflects "now"
            // and races key-handling on macOS — that's what broke
            // Shift+↑/↓ range selection in tree mode. `.repeat` keeps
            // a held arrow key auto-scrolling like Finder does.
            .onKeyPress(.downArrow, phases: [.down, .repeat]) { keyPress in
                guard viewModel.renamingEntryID == nil else { return .ignored }
                handleArrow(by: 1, extending: keyPress.modifiers.contains(.shift), proxy: proxy)
                return .handled
            }
            .onKeyPress(.upArrow, phases: [.down, .repeat]) { keyPress in
                guard viewModel.renamingEntryID == nil else { return .ignored }
                handleArrow(by: -1, extending: keyPress.modifiers.contains(.shift), proxy: proxy)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard viewModel.renamingEntryID == nil else { return .ignored }
                handleRightArrow(proxy: proxy)
                return .handled
            }
            .onKeyPress(.leftArrow) {
                guard viewModel.renamingEntryID == nil else { return .ignored }
                handleLeftArrow(proxy: proxy)
                return .handled
            }
            .onKeyPress(.return, phases: [.down]) { keyPress in
                guard viewModel.renamingEntryID == nil else { return .ignored }
                if !isFocused { onFocus() }
                if keyPress.modifiers.contains(.command),
                   let entry = viewModel.selectedEntry, entry.isDirectory {
                    AppCommand.openURLInNewTab(url: entry.url).post()
                } else {
                    viewModel.openSelected()
                }
                return .handled
            }
            .onKeyPress(.space) {
                guard viewModel.renamingEntryID == nil else { return .ignored }
                if !isFocused { onFocus() }
                let urls = viewModel.selectedURLs
                guard !urls.isEmpty else { return .ignored }
                QuickLookManager.shared.toggle(urls: urls)
                return .handled
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                } else if viewModel.entries.isEmpty {
                    Text("No items")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.labelTertiary)
                }
            }
        }
    }

    /// ↑/↓: walk the flat DFS of currently-visible tree rows. The VM
    /// already does the right thing in tree mode; we just need to keep
    /// the moved-to anchor on screen. `extending` is read off the
    /// captured `KeyPress` so Shift+arrow growth doesn't race the
    /// global modifier state.
    private func handleArrow(by offset: Int, extending: Bool, proxy: ScrollViewProxy) {
        if !isFocused { onFocus() }
        viewModel.moveSelection(by: offset, extending: extending)
        if let anchor = viewModel.selectionAnchor {
            proxy.scrollTo(anchor, anchor: .center)
        }
    }

    /// →: expand a collapsed folder; if already expanded, descend to its
    /// first child. Files become a no-op. Finder/VS Code convention.
    private func handleRightArrow(proxy: ScrollViewProxy) {
        if !isFocused { onFocus() }
        guard let entry = viewModel.selectedEntry, entry.isDirectory else { return }
        if !viewModel.isExpanded(entry.url) {
            viewModel.toggleExpanded(entry.url)
        } else if let firstChild = viewModel.treeChildren[entry.url.path]
            .flatMap({ FileEntry.treeOrdered($0).first })
        {
            viewModel.replaceSelection(firstChild.id)
            proxy.scrollTo(firstChild.id, anchor: .center)
        }
    }

    /// ←: collapse an expanded folder; otherwise jump to the parent row.
    /// Parent = the directory entry whose URL matches the selected
    /// entry's parent path (anywhere in `entries` or `treeChildren`).
    private func handleLeftArrow(proxy: ScrollViewProxy) {
        if !isFocused { onFocus() }
        guard let entry = viewModel.selectedEntry else { return }
        if entry.isDirectory, viewModel.isExpanded(entry.url) {
            viewModel.toggleExpanded(entry.url)
            return
        }
        let parentURL = entry.url.deletingLastPathComponent()
        let candidates = viewModel.entries + viewModel.treeChildren.values.flatMap { $0 }
        if let parent = candidates.first(where: { $0.url == parentURL }) {
            viewModel.replaceSelection(parent.id)
            proxy.scrollTo(parent.id, anchor: .center)
        }
    }

    /// Fall-back when `treeChildren[root]` hasn't been populated yet —
    /// rely on the existing flat enumeration `viewModel.entries`. The VM
    /// populates `treeChildren[root]` on every `entries` change, so this
    /// only fires on the very first render before that assignment lands.
    private func entriesForRoot() -> [FileEntry]? {
        viewModel.entries.isEmpty ? nil : viewModel.entries
    }

    /// Returns `AnyView` to break the opaque-type recursion: a `some View`
    /// can't be defined in terms of itself, and `treeRow` calls itself for
    /// expanded folders. The erasure cost here is negligible — only the
    /// rows actually on screen materialize because the parent is a
    /// `LazyVStack`.
    @ViewBuilder
    private func treeRow(_ entry: FileEntry, depth: Int) -> AnyView {
        AnyView(treeRowBody(entry, depth: depth))
    }

    @ViewBuilder
    private func treeRowBody(_ entry: FileEntry, depth: Int) -> some View {
        let isExpanded = entry.isDirectory && viewModel.isExpanded(entry.url)
        let isSelected = viewModel.selection.contains(entry.id)

        TreeRow(
            entry: entry,
            depth: depth,
            isExpanded: isExpanded,
            isSelected: isSelected,
            paneIsFocused: isFocused,
            isRenaming: viewModel.renamingEntryID == entry.id,
            renameDraft: Binding(
                get: { viewModel.renameDraft },
                set: { viewModel.renameDraft = $0 }
            ),
            onChevronTap: {
                if !isFocused { onFocus() }
                viewModel.toggleExpanded(entry.url)
            },
            commitRename: {
                viewModel.commitRename()
                // Same deferred-focus reason as the list view's
                // commit path (`BrowserPaneView.swift`): the row's
                // TextField unmounts as `entries` reload, so we
                // hop one runloop turn before restoring keyboard
                // focus to the tree list — otherwise ↑/↓ silently
                // no-op until the user clicks.
                DispatchQueue.main.async { treeFocused = true }
            },
            cancelRename: {
                viewModel.cancelRename()
                DispatchQueue.main.async { treeFocused = true }
            },
            tabRename: { forward in
                viewModel.beginRenameAdjacent(forward: forward)
                if viewModel.renamingEntryID == nil {
                    DispatchQueue.main.async { treeFocused = true }
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // ⌘+double-click on a folder opens it in a new tab —
            // mirrors Finder and the list view's matching behavior.
            // Plain double-click navigates into the folder / launches
            // the file as before.
            if NSEvent.modifierFlags.contains(.command), entry.isDirectory {
                AppCommand.openURLInNewTab(url: entry.url).post()
            } else if entry.isDirectory {
                viewModel.openFolder(entry.url)
            } else {
                viewModel.open(entry)
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            if !isFocused { onFocus() }
            let mods = NSEvent.modifierFlags
            // ⌘+single-click on a folder used to short-circuit to
            // "open in new tab" here. That collided with the new
            // ⌘+double-click new-tab path — every double-click fired
            // single-click twice via simultaneousGesture, producing
            // two duplicate tabs. Treat ⌘+single-click as the
            // multi-select toggle just like the list view does; new
            // tabs come from ⌘+double-click and ⌘+Enter instead.
            if mods.contains(.shift) {
                viewModel.extendSelection(to: entry.id)
            } else if mods.contains(.command) {
                viewModel.toggleSelection(entry.id)
            } else {
                viewModel.replaceSelection(entry.id)
            }
            // Plain row click no longer auto-toggles the chevron —
            // the chevron has its own hit target now (VS Code parity)
            // so users can select a folder without forcing it open.
        })
        // Drag SOURCE — same AppKit-driven pasteboard path the list
        // view uses, so dragging a tree row into Terminal / cmux /
        // another app yields the real file URL (not a SwiftUI
        // drag-promise cache copy). Tree view is single-row so
        // `multiURLs` stays empty; the primary URL is enough.
        .appKitFileDrag(primary: entry.url, normalizeHangul: normalizeHangulOnDragOut)
        .inactiveDragSource(
            primary: entry.url,
            normalizeHangul: normalizeHangulOnDragOut,
            onClick: { _ in
                if !isFocused { onFocus() }
                viewModel.replaceSelection(entry.id)
            },
            onDoubleClick: { _ in
                if entry.isDirectory {
                    viewModel.openFolder(entry.url)
                } else {
                    viewModel.open(entry)
                }
            }
        )
        // Right-click selects the clicked row before the menu shows
        // (Finder parity). Tree view is single-row interaction so we
        // always replace selection with the clicked row.
        .background(
            RightClickAware {
                viewModel.replaceSelection(entry.id)
                if !isFocused { onFocus() }
            }
        )
        .contextMenu {
            if entry.isDirectory {
                Button(isExpanded ? "Collapse" : "Expand") {
                    viewModel.toggleExpanded(entry.url)
                }
                Divider()
            }
            // Tree view is single-row interaction (no multi-select), so
            // the menu always operates on just the clicked entry.
            FileEntryContextMenu(
                viewModel: viewModel,
                targets: [entry],
                primaryName: entry.name
            )
        }
        // ScrollViewProxy.scrollTo(id) needs each row tagged so arrow-key
        // nav can keep the moved-to row visible.
        .id(entry.id)

        if isExpanded {
            if let error = viewModel.treeLoadErrors[entry.url.path] {
                HStack {
                    Text(error).lineLimit(2)
                    Button("Retry") { viewModel.retryTreeChildren(entry.url) }
                }
                .font(.caption)
                .padding(.leading, CGFloat(depth + 1) * 14 + 24)
            } else if viewModel.loadingTreePaths.contains(entry.url.path) {
                HStack {
                    ProgressView().controlSize(.mini)
                    Text("Loading…").font(.caption)
                }
                .padding(.leading, CGFloat(depth + 1) * 14 + 24)
            } else if let children = viewModel.treeChildren[entry.url.path] {
                ForEach(FileEntry.treeOrdered(children)) { child in
                    treeRow(child, depth: depth + 1)
                }
            }
        }
    }
}

// MARK: - Single row

private struct TreeRow: View {
    let entry: FileEntry
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    let paneIsFocused: Bool
    let isRenaming: Bool
    @Binding var renameDraft: String
    /// Fired when the user clicks the disclosure chevron only.
    /// The row-level tap gesture handles selection — VS Code-style
    /// separation so clicking a folder's name selects without
    /// auto-expanding it.
    let onChevronTap: () -> Void
    let commitRename: () -> Void
    let cancelRename: () -> Void
    /// Tab / Shift-Tab while renaming — commit then advance to the
    /// next / previous visible tree row (Finder-style).
    let tabRename: (_ forward: Bool) -> Void

    private static let indentPerDepth: CGFloat = 14

    var body: some View {
        HStack(spacing: 4) {
            // Disclosure chevron — fixed slot for files too so names align
            // vertically across folder/file rows at the same depth.
            // Folders carry their own tap target so name-clicks select
            // without forcing the folder open / closed.
            Group {
                if entry.isDirectory {
                    // Button intercepts the click reliably; `.onTapGesture`
                    // on the chevron used to lose the event when the
                    // parent row's `.simultaneousGesture(TapGesture)`
                    // and `.onTapGesture(count: 2)` both competed for
                    // the same hit. `.buttonStyle(.plain)` keeps the
                    // visual identical to the previous bare Image.
                    Button {
                        onChevronTap()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.Color.labelSecondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 16, height: 16)
                }
            }

            FileRowIcon(
                entry: entry,
                isSelected: isSelected,
                paneIsFocused: paneIsFocused
            )

            if isRenaming {
                RenameTextField(
                    text: $renameDraft,
                    isDirectory: entry.isDirectory,
                    onCommit: commitRename,
                    onCancel: cancelRename,
                    onTab: tabRename
                )
                .frame(maxWidth: .infinity)
                .renameFieldChrome()
            } else {
                Text(entry.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                TagDotView(entry: entry)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 8 + CGFloat(depth) * Self.indentPerDepth)
        .padding(.trailing, 6)
        .frame(minHeight: Theme.Metrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(rowBackground)
                .padding(.horizontal, 4)
        )
    }

    private var rowBackground: Color {
        // Drop the selection fill while editing so the rename field's
        // accent ring is the dominant cue (mirrors the list view).
        if isRenaming { return .clear }
        if !isSelected { return .clear }
        return paneIsFocused ? Theme.Color.selection : Theme.Color.selectionInactive
    }

    private var textColor: Color {
        isSelected && paneIsFocused ? .white : Theme.Color.label
    }
}
