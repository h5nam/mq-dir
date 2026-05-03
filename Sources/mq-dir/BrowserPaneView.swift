import AppKit
import SwiftUI

struct BrowserPaneView: View {
    let index: Int
    @ObservedObject var viewModel: FolderBrowserViewModel
    let isFocused: Bool
    let onFocus: () -> Void

    @State private var paneIsDropTargeted = false
    @State private var rowDropTargeted: FileEntry.ID?

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            paneHeader
            columnHeader
            content
        }
        .background(Theme.Color.paneBg)
        .overlay(
            Rectangle()
                .strokeBorder(
                    paneBorderColor,
                    lineWidth: Theme.Metrics.focusBorderWidth
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
    }

    private var paneBorderColor: Color {
        if paneIsDropTargeted && rowDropTargeted == nil { return Theme.Color.accent }
        if isFocused { return Theme.Color.accent }
        return .clear
    }

    // MARK: Tab bar (Safari-style; single tab in M1)

    private var tabBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.accent.opacity(0.85))
                Text(viewModel.folderURL?.lastPathComponent ?? "Untitled")
                    .font(Theme.Font.tab)
                    .foregroundStyle(Theme.Color.label)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: Theme.Metrics.tabBarHeight)
            .background(Color.white.opacity(0.04))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Theme.Color.separatorFaint)
                    .frame(width: 0.5)
            }

            Spacer(minLength: 0)

            Button {
                viewModel.chooseFolder()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.labelSecondary)
                    .frame(width: 24, height: Theme.Metrics.tabBarHeight)
            }
            .buttonStyle(.plain)
            .help("Open Folder in Pane \(index + 1)")
        }
        .frame(height: Theme.Metrics.tabBarHeight)
        .background(Theme.Color.tabBarBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Color.separator).frame(height: 0.5)
        }
    }

    // MARK: Folder header strip

    private var paneHeader: some View {
        HStack(spacing: 6) {
            if let url = viewModel.folderURL {
                Text(url.lastPathComponent)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Color.label)
                Text("—")
                    .foregroundStyle(Theme.Color.labelTertiary)
                Text(itemCountLabel)
                    .foregroundStyle(Theme.Color.labelSecondary)
            } else {
                Text("No folder open")
                    .foregroundStyle(Theme.Color.labelTertiary)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 10)
        .frame(height: Theme.Metrics.paneHeaderHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Color.separatorFaint).frame(height: 0.5)
        }
    }

    private var itemCountLabel: String {
        if viewModel.isFiltering {
            if viewModel.isSearching { return "searching\u{2026}" }
            let count = viewModel.visibleEntries.count
            return "\(count) match\(count == 1 ? "" : "es")"
        }
        let total = viewModel.entries.count
        return "\(total) item\(total == 1 ? "" : "s")"
    }

    private var emptyStateLabel: String {
        if viewModel.isFiltering {
            if viewModel.isSearching { return "Searching\u{2026}" }
            let trimmed = viewModel.searchQuery.trimmingCharacters(in: .whitespaces)
            return "No matches for \u{201C}\(trimmed)\u{201D}"
        }
        return "No items"
    }

    /// While a recursive search is active, show the entry's parent folder
    /// path relative to the search root so users can tell which subfolder a
    /// hit lives in. Direct children of the search root get no subtitle.
    private func searchSubtitle(for entry: FileEntry) -> String? {
        guard viewModel.isFiltering, let root = viewModel.folderURL else { return nil }
        let parent = entry.url.deletingLastPathComponent()
        guard parent != root else { return nil }
        let rootPrefix = root.path(percentEncoded: false)
        let parentPath = parent.path(percentEncoded: false)
        guard parentPath.hasPrefix(rootPrefix) else { return parentPath }
        let stripped = parentPath.dropFirst(rootPrefix.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return stripped.isEmpty ? nil : stripped
    }

    // MARK: Column header

    private var columnHeader: some View {
        HStack(spacing: 0) {
            sortHeader("Name", key: .name, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            ColumnResizeHandle { delta in
                let next = (viewModel.columnWidths.modified - delta)
                    .clamped(to: PaneColumnWidths.modifiedRange)
                viewModel.columnWidths.modified = next
            }

            sortHeader("Modified", key: .modified, alignment: .leading)
                .frame(width: viewModel.columnWidths.modified, alignment: .leading)

            ColumnResizeHandle { delta in
                let nextMod = viewModel.columnWidths.modified + delta
                let nextSize = viewModel.columnWidths.size - delta
                if PaneColumnWidths.modifiedRange.contains(nextMod),
                   PaneColumnWidths.sizeRange.contains(nextSize) {
                    viewModel.columnWidths.modified = nextMod
                    viewModel.columnWidths.size = nextSize
                }
            }

            sortHeader("Size", key: .size, alignment: .trailing)
                .frame(width: viewModel.columnWidths.size, alignment: .trailing)

            ColumnResizeHandle { delta in
                let nextSize = viewModel.columnWidths.size + delta
                let nextKind = viewModel.columnWidths.kind - delta
                if PaneColumnWidths.sizeRange.contains(nextSize),
                   PaneColumnWidths.kindRange.contains(nextKind) {
                    viewModel.columnWidths.size = nextSize
                    viewModel.columnWidths.kind = nextKind
                }
            }

            sortHeader("Kind", key: .kind, alignment: .leading)
                .frame(width: viewModel.columnWidths.kind, alignment: .leading)
        }
        .font(Theme.Font.columnHeader)
        .foregroundStyle(Theme.Color.labelSecondary)
        .padding(.horizontal, 6)
        .frame(height: Theme.Metrics.columnHeaderHeight)
        .background(Theme.Color.columnHeaderBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Color.separator).frame(height: 0.5)
        }
    }

    private func sortHeader(_ title: String, key: FileEntrySortKey, alignment: HorizontalAlignment) -> some View {
        let isActive = viewModel.sortKey == key
        return Button {
            viewModel.setSort(key)
        } label: {
            HStack(spacing: 4) {
                if alignment == .trailing { Spacer(minLength: 0) }
                Text(title)
                    .foregroundStyle(isActive ? Theme.Color.label : Theme.Color.labelSecondary)
                if isActive {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.Color.labelSecondary)
                }
                if alignment == .leading { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if viewModel.folderURL == nil {
            emptyState
        } else if let errorMessage = viewModel.errorMessage {
            errorState(errorMessage)
        } else {
            fileList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 26))
                .foregroundStyle(Theme.Color.labelTertiary)
            Text("Open a folder")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.labelSecondary)
            Button("Open Folder…") { viewModel.chooseFolder() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            Text("Could not open folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.label)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.labelSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { viewModel.reload() }
                .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.visibleEntries) { entry in
                    rowView(for: entry)
                }
            }
            .padding(.vertical, 2)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else if viewModel.visibleEntries.isEmpty {
                Text(emptyStateLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.labelTertiary)
            }
        }
        // Drop on the pane background → drop INTO the current folder.
        // We use the lower-level NSItemProvider API so a single drop can carry
        // a multi-item internal selection (see DragDropSupport).
        .onDrop(of: DragDropSupport.acceptedDropTypes, isTargeted: $paneIsDropTargeted) { providers in
            guard let folder = viewModel.folderURL else { return false }
            let modifiers = NSEvent.modifierFlags
            Task {
                let urls = await DragDropSupport.resolveURLs(from: providers)
                guard !urls.isEmpty else { return }
                await MainActor.run {
                    viewModel.acceptDrop(
                        urls,
                        into: folder,
                        copy: modifiers.contains(.option)
                    )
                }
            }
            return true
        }
    }

    @ViewBuilder
    private func rowView(for entry: FileEntry) -> some View {
        let isSelected = viewModel.selection.contains(entry.id)
        let isRowDropTarget = entry.isDirectory && rowDropTargeted == entry.id

        let row = FileEntryRow(
            entry: entry,
            isSelected: isSelected,
            paneIsFocused: isFocused,
            isDropTarget: isRowDropTarget,
            columnWidths: viewModel.columnWidths,
            subtitle: searchSubtitle(for: entry)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { viewModel.open(entry) }
        .simultaneousGesture(TapGesture().onEnded {
            if !isFocused { onFocus() }
            let mods = NSEvent.modifierFlags
            if mods.contains(.shift) {
                viewModel.extendSelection(to: entry.id)
            } else if mods.contains(.command) {
                viewModel.toggleSelection(entry.id)
            } else {
                viewModel.replaceSelection(entry.id)
            }
        })
        .contextMenu {
            Button("Open") { viewModel.open(entry) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
        }
        // Drag SOURCE: ship one NSItemProvider that carries the row's URL as
        // public.file-url for external apps, plus a private multi-URL payload
        // when this row is part of a multi-selection (internal pane↔pane).
        .onDrag {
            let multi = (isSelected && viewModel.selection.count > 1)
                ? viewModel.selectedURLs
                : []
            return DragDropSupport.makeItemProvider(primary: entry.url, multiURLs: multi)
        }

        if entry.isDirectory {
            // Folder rows are drop TARGETS — drop INTO the subfolder, with
            // a per-row isTargeted state for the highlight.
            row.onDrop(
                of: DragDropSupport.acceptedDropTypes,
                isTargeted: Binding(
                    get: { rowDropTargeted == entry.id },
                    set: { rowDropTargeted = $0 ? entry.id : nil }
                )
            ) { providers in
                let modifiers = NSEvent.modifierFlags
                Task {
                    let urls = await DragDropSupport.resolveURLs(from: providers)
                    guard !urls.isEmpty else { return }
                    await MainActor.run {
                        viewModel.acceptDrop(
                            urls,
                            into: entry.url,
                            copy: modifiers.contains(.option)
                        )
                    }
                }
                return true
            }
        } else {
            row
        }
    }
}

// MARK: Row

private struct FileEntryRow: View {
    let entry: FileEntry
    let isSelected: Bool
    let paneIsFocused: Bool
    let isDropTarget: Bool
    let columnWidths: PaneColumnWidths
    /// Optional second line under the name — used by recursive search to show
    /// where in the tree a hit lives. `nil` keeps the row at single-line height.
    let subtitle: String?

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: FileIconStyle.symbol(for: entry))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected && paneIsFocused
                                     ? Color.white
                                     : FileIconStyle.tint(for: entry))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(Theme.Font.body)
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(secondaryColor)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Spacer matching the header's resize-handle width so columns
            // stay vertically aligned with the column dividers.
            Color.clear.frame(width: 6)

            Text(Self.modifiedDateFormatter.string(from: entry.modificationDate))
                .font(.system(size: 11))
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .frame(width: columnWidths.modified, alignment: .leading)

            Color.clear.frame(width: 6)

            Text(Self.sizeFormatter.string(fromByteCount: entry.size))
                .font(.system(size: 11))
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .frame(width: columnWidths.size, alignment: .trailing)

            Color.clear.frame(width: 6)

            Text(entry.kind)
                .font(.system(size: 11))
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: columnWidths.kind, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, subtitle == nil ? 0 : 2)
        .frame(minHeight: Theme.Metrics.rowHeight)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(rowBackground)
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Color.accent.opacity(0.18))
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.Color.accent, lineWidth: 1)
                }
            }
            .padding(.horizontal, 4)
        )
    }

    private var rowBackground: Color {
        if !isSelected { return .clear }
        return paneIsFocused ? Theme.Color.selection : Theme.Color.selectionInactive
    }

    private var textColor: Color {
        isSelected && paneIsFocused ? .white : Theme.Color.label
    }

    private var secondaryColor: Color {
        if isSelected && paneIsFocused {
            return Color.white.opacity(0.85)
        }
        return Theme.Color.labelSecondary
    }

    private static let modifiedDateFormatter = ModifiedDateFormatter()
    private static let sizeFormatter = FileSizeFormatter()
}

private struct ModifiedDateFormatter {
    private let formatter: DateFormatter

    init() {
        formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
    }

    func string(from date: Date?) -> String {
        guard let date else { return "—" }
        return formatter.string(from: date)
    }
}

private struct FileSizeFormatter {
    private let formatter: ByteCountFormatter

    init() {
        formatter = ByteCountFormatter()
        formatter.countStyle = .file
    }

    func string(fromByteCount size: Int64?) -> String {
        guard let size else { return "—" }
        return formatter.string(fromByteCount: size)
    }
}

// MARK: Column resize handle

private struct ColumnResizeHandle: View {
    let onChange: (CGFloat) -> Void

    @State private var lastTranslation: CGFloat = 0
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6, height: Theme.Metrics.columnHeaderHeight)
            .overlay(
                Rectangle()
                    .fill(isHovered || isDragging ? Theme.Color.accent.opacity(0.7) : Theme.Color.separator)
                    .frame(width: isHovered || isDragging ? 1 : 0.5)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            lastTranslation = 0
                            NSCursor.resizeLeftRight.push()
                        }
                        let delta = value.translation.width - lastTranslation
                        lastTranslation = value.translation.width
                        onChange(delta)
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastTranslation = 0
                        NSCursor.pop()
                    }
            )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
