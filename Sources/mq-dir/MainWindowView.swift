import AppKit
import SwiftUI

struct MainWindowView: View {
    @ObservedObject private var fileWork = FileWorkCenter.shared
    @State private var folderComparison: FolderComparisonRequest?
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var repoCallout: RepoCalloutController
    @StateObject private var integrations: IntegrationsSidebarModel

    @StateObject private var pane0: PaneTabsViewModel
    @StateObject private var pane1: PaneTabsViewModel
    @StateObject private var pane2: PaneTabsViewModel
    @StateObject private var pane3: PaneTabsViewModel
    @StateObject private var sidebar: SidebarViewModel

    @State private var layout: PaneLayout
    @State private var focusedPaneIndex: Int
    @State private var sidebarSelection: URL?
    @FocusState private var searchFocused: Bool
    /// Gates the real TextField behind a tap. While false the field renders
    /// as a static placeholder so SwiftUI doesn't auto-promote it to the
    /// window's first responder on appearance.
    @State private var searchActive: Bool = false

    /// Owning ID of the project this view instance was constructed for.
    /// `mqdirApp` keys this view on `workspace.workspace.activeProjectID`,
    /// so a project switch tears down the old `MainWindowView` (and its
    /// `@StateObject` panes) and instantiates a fresh one — no need to
    /// reload pane state in place.
    private let projectID: UUID

    /// Last persistable state pushed into the workspace, cached so
    /// `scheduleSave()` can early-return when an `objectWillChange` carried
    /// no persistable delta. Every pane VM forwards *every* nested tab's
    /// `@Published` change (selection moves, `isLoading` flips, search
    /// keystrokes, rename-draft edits) — most of which never touch the
    /// serialized snapshot. Without this gate a held arrow key rebuilds and
    /// re-pushes a full 4-pane `WindowState` on every key-repeat. `WindowState`
    /// and `Favorite` are `Equatable`, so the compare is a cheap value-type
    /// walk. `nil` until the first save schedules so the very first mutation
    /// always lands.
    @State private var lastScheduledState: WindowState?
    @State private var lastScheduledFavorites: [Favorite]?

    /// Cached free-space string for the focused pane's volume. `freeSpaceString()`
    /// did a synchronous `volumeAvailableCapacityForImportantUsage` stat on
    /// every status-bar re-render (so a stat on each keystroke, selection
    /// move, hover); that's per-render disk I/O on the main actor. We recompute
    /// only when the focused folder changes (a new folder can sit on a
    /// different volume) and on filesystem-change broadcasts (so a big copy
    /// finishing updates the number). `nil` until the first computation lands.
    @State private var freeSpaceCache: String?

    init(
        workspace: WorkspaceManager,
        updateManager: UpdateManager,
        repoCallout: RepoCalloutController
    ) {
        self.workspace = workspace
        self._integrations = StateObject(wrappedValue: IntegrationsSidebarModel(provider: workspace.workspace.settings.integrationProvider))
        self.updateManager = updateManager
        self.repoCallout = repoCallout
        let project = workspace.activeProject
        self.projectID = project.id
        let state = project.state

        self._layout = State(initialValue: state.layout)
        self._focusedPaneIndex = State(
            initialValue: min(max(state.focusedPaneIndex, 0), state.layout.paneCount - 1)
        )

        // Always rehydrate four panes — any layout shrink stashes the
        // off-screen pane state so it returns when the layout grows back.
        // Each pane carries its own tab list; the VM forwards every nested
        // tab's objectWillChange so any change in any tab schedules a save.
        let panes = state.panes
        self._pane0 = StateObject(wrappedValue: PaneTabsViewModel(state: panes[0]))
        self._pane1 = StateObject(wrappedValue: PaneTabsViewModel(state: panes[1]))
        self._pane2 = StateObject(wrappedValue: PaneTabsViewModel(state: panes[2]))
        self._pane3 = StateObject(wrappedValue: PaneTabsViewModel(state: panes[3]))

        // Sidebar mirrors the workspace-level Favorites list. Mutations
        // round-trip back through `workspace.setFavorites` (see the save
        // trigger in `SaveTriggers`).
        self._sidebar = StateObject(
            wrappedValue: SidebarViewModel(favorites: workspace.workspace.favorites)
        )
    }

    var body: some View {
        windowChrome
            .alert("Workspace recovery", isPresented: Binding(
                get: { workspace.recoveryMessage != nil },
                set: { if !$0 { workspace.recoveryMessage = nil } }
            )) {
                Button("OK") { workspace.recoveryMessage = nil }
            } message: {
                Text(workspace.recoveryMessage ?? "")
            }
            .background(Theme.Color.windowBg)
            .sheet(item: $folderComparison) { FolderComparisonView(request: $0) }
            .onDisappear { scheduleSave() }
            .onReceive(NotificationCenter.default.publisher(for: ExternalFolderRequests.changed)) { _ in openExternalFolders() }
            .onChange(of: integrations.provider) { _, provider in workspace.setIntegrationProvider(provider) }
            .modifier(SaveTriggers(
                pane0: pane0, pane1: pane1, pane2: pane2, pane3: pane3,
                sidebar: sidebar,
                layout: $layout,
                focusedPaneIndex: $focusedPaneIndex,
                scheduleSave: scheduleSave
            ))
            .modifier(NavigationNotifications(
                focusedPane: focusedPane,
                searchActive: $searchActive,
                searchFocused: $searchFocused,
                sidebar: sidebar
            ))
            .modifier(EditMenuNotifications(
                focusedPane: focusedPane,
                normalizeHangul: workspace.workspace.settings.normalizeHangulOnDragOut
            ))
            .modifier(EditFileActionsNotifications(
                focusedPane: focusedPane,
                normalizeHangul: workspace.workspace.settings.normalizeHangulOnDragOut
            ))
            .modifier(PaneFocusNotifications(layout: layout, focusedPaneIndex: $focusedPaneIndex))
            .modifier(TabNotifications(focusedPaneVM: focusedPaneVM))
            .modifier(GlobalNotifications(
                allPanes: [pane0, pane1, pane2, pane3],
                saveSynchronously: saveSynchronously
            ))
            .onAppear {
                // Hand the live pane VMs to the cross-pane tab drag
                // coordinator so a drop on a different pane can detach
                // from the source pane and attach here. Re-runs on
                // project switch (this view is keyed on activeProjectID
                // and gets re-instantiated, so the coordinator gets
                // fresh references for the active project).
                TabDragCoordinator.shared.register(panes: [pane0, pane1, pane2, pane3])
                // Once-per-process launch counter for the repo callout
                // gate. The controller guards against re-fires on
                // project switch.
                repoCallout.recordLaunch()
                openExternalFolders()
            }
    }

    private func openExternalFolders() {
        for url in ExternalFolderRequests.consume() {
            focusedPaneVM.newTab()
            focusedPaneVM.activeTab.openExternalURL(url)
        }
    }

    private var windowChrome: some View {
        HSplitView {
            SidebarView(
                viewModel: sidebar,
                workspace: workspace,
                updateManager: updateManager,
                repoCallout: repoCallout,
                integrations: integrations,
                selectedURL: $sidebarSelection,
                // VM-memoized — see `FolderBrowserViewModel.tagSummaries`.
                tagsSummary: focusedPane.tagSummaries,
                onTagSelected: { tag in
                    // Dedicated tag filter: shows only current-folder entries
                    // whose `tagNames` contain this exact name — so a file
                    // tagged "업무" surfaces regardless of its filename, which
                    // the old substring-into-searchQuery hack couldn't do.
                    // Clicking the already-active tag clears the filter
                    // (toggle), matching the sidebar's "click to filter,
                    // click again to clear" affordance.
                    focusedPane.tagFilter = (focusedPane.tagFilter == tag) ? nil : tag
                }
            ) { url in
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                focusedPane.openFolder(url)
            }
            .frame(minWidth: 160, idealWidth: Theme.Metrics.sidebarWidth, maxWidth: 280)

            VStack(spacing: 0) {
                toolbar
                Divider().background(Theme.Color.separator)
                paneGrid
                Divider().background(Theme.Color.separator)
                globalStatusBar
            }
            .background(Theme.Color.windowBg)
        }
    }

    // MARK: Persistence wiring

    /// Build a snapshot of every persistable bit of window state. Favorites
    /// are excluded — they live on `WorkspaceManager` because they're
    /// shared across all projects.
    @MainActor
    private func snapshot() -> WindowState {
        WindowState(
            layout: layout,
            focusedPaneIndex: focusedPaneIndex,
            panes: [
                pane0.snapshot(),
                pane1.snapshot(),
                pane2.snapshot(),
                pane3.snapshot(),
            ]
        )
    }

    /// Push the current snapshot into the project that owns this view.
    /// `WorkspaceManager` owns the debounce window and the disk write —
    /// this view just keeps the in-memory model current after every
    /// observable mutation.
    ///
    /// Gated on a value-equality compare against the last-pushed snapshot:
    /// the pane VMs fan out *every* transient `@Published` change (selection
    /// moves do persist via `selectedURLPaths`, but `isLoading` / `isSearching`
    /// / `searchResults` / `renameDraft` churn does not), so without this most
    /// emissions would rebuild and re-push an identical `WindowState`. The
    /// snapshot itself is still built per emission — that's unavoidable while
    /// the change signal is a bare `objectWillChange` — but the `updateProject`
    /// / `setFavorites` round-trip (which each schedule a 500 ms debounced disk
    /// write) only fires for the half that actually changed.
    @MainActor
    private func scheduleSave() {
        let state = snapshot()
        if state != lastScheduledState {
            workspace.updateProject(id: projectID) { $0.state = state }
            lastScheduledState = state
        }
        guard workspace.workspace.activeProjectID == projectID else { return }
        // Favorites edit through the sidebar VM also feed in here so the
        // workspace's cross-project list stays in sync.
        let favorites = sidebar.favorites
        if favorites != lastScheduledFavorites {
            workspace.setFavorites(favorites)
            lastScheduledFavorites = favorites
        }
    }

    /// On app termination — flush the latest snapshot synchronously so
    /// the runloop teardown can't cancel the debounced disk write.
    @MainActor
    private func saveSynchronously() {
        let state = snapshot()
        workspace.updateProject(id: projectID) { $0.state = state }
        if workspace.workspace.activeProjectID == projectID {
            workspace.setFavorites(sidebar.favorites)
        }
        workspace.saveSynchronously()
    }

    // MARK: Toolbar (compact, ~38pt)

    private var toolbar: some View {
        HStack(spacing: 6) {
            // Spacer for traffic-light area on the left edge of the window.
            Spacer().frame(width: 64)

            Button {
                fileWork.isPresented.toggle()
            } label: {
                Image(systemName: "list.bullet.clipboard")
            }
            .help("File operations")
            .accessibilityLabel("File operations")
            .popover(isPresented: $fileWork.isPresented) { FileWorkPanel(center: fileWork) }
            ToolbarIconButton(symbol: "chevron.left", help: "Back (⌘[)") { focusedPane.goBack() }
                .disabled(!focusedPane.canGoBack)
            ToolbarIconButton(symbol: "chevron.right", help: "Forward (⌘])") { focusedPane.goForward() }
                .disabled(!focusedPane.canGoForward)
            ToolbarIconButton(symbol: "chevron.up", help: "Parent Folder (⌘↑)") { focusedPane.openParentFolder() }
                .disabled(focusedPane.folderURL == nil)
            ToolbarIconButton(symbol: "arrow.clockwise", help: "Reload (⌘R)") { focusedPane.reload() }
                .disabled(focusedPane.folderURL == nil)

            breadcrumb

            searchField
            SearchOptionsMenu(model: focusedPane, workspace: workspace,
                projectRoots: [pane0, pane1, pane2, pane3].flatMap { $0.tabs.compactMap(\.folderURL) })

            Menu {
                ForEach(0..<layout.paneCount, id: \.self) { index in
                    if index != focusedPaneIndex, let other = paneVM(at: index).activeTab.folderURL,
                       let current = focusedPane.folderURL {
                        Button("Compare with Pane \(index + 1) — \(other.lastPathComponent)") {
                            folderComparison = FolderComparisonRequest(left: current, right: other)
                        }
                    }
                }
            } label: { Image(systemName: "square.split.2x1") }
            .help("Compare visible folders")
            .disabled(layout.paneCount < 2 || focusedPane.folderURL == nil)
            layoutSegmentedControl
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.toolbarHeight)
        .background(Theme.Color.toolbarBg)
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            if let url = focusedPane.folderURL {
                let components = Array(url.pathComponents.filter { $0 != "/" }.suffix(3))
                if components.isEmpty {
                    Text("/").font(Theme.Font.breadcrumb).foregroundStyle(Theme.Color.label)
                } else {
                    ForEach(Array(components.enumerated()), id: \.offset) { idx, name in
                        if idx > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Color.labelTertiary)
                        }
                        Text(name)
                            .layoutPriority(idx == components.count - 1 ? 1 : 0)
                            .font(Theme.Font.breadcrumb)
                            .foregroundStyle(idx == components.count - 1
                                             ? Theme.Color.label
                                             : Theme.Color.labelSecondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("No Folder")
                    .font(Theme.Font.breadcrumb)
                    .foregroundStyle(Theme.Color.labelTertiary)
            }
            Spacer(minLength: 0)
            breadcrumbCopyButton
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Theme.Color.separator, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { focusedPane.chooseFolder() }
        .contextMenu { breadcrumbContextMenu }
    }

    /// Trailing clipboard glyph that copies the current folder's POSIX
    /// path in one click — Windows File Explorer's "address bar copy"
    /// pattern. Sits inside the breadcrumb pill so it's at hand when
    /// the user is already looking at the path. Right-click on the
    /// pill itself surfaces the longer menu for the open-elsewhere
    /// actions.
    @ViewBuilder
    private var breadcrumbCopyButton: some View {
        Button {
            focusedPane.copyCurrentFolderPath()
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Color.labelTertiary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy Path")
        .disabled(focusedPane.folderURL == nil)
    }

    @ViewBuilder
    private var breadcrumbContextMenu: some View {
        Button("Copy Path") { focusedPane.copyCurrentFolderPath() }
            .disabled(focusedPane.folderURL == nil)
        Divider()
        Button("Open in Terminal") { focusedPane.openCurrentFolderInTerminal() }
            .disabled(focusedPane.folderURL == nil)
        if workspace.workspace.settings.integrationProvider == .cmux, focusedPane.canOpenInCmux {
            Button("Open in cmux") { focusedPane.openCurrentFolderInCmux() }
                .disabled(focusedPane.folderURL == nil)
        } else if let app = WorkspaceIntegrationClient.applicationURL(for: workspace.workspace.settings.integrationProvider) {
            Button("Open \(workspace.workspace.settings.integrationProvider.title)") { NSWorkspace.shared.open(app) }
        }
        Button("Open in Finder") { focusedPane.openCurrentFolderInFinder() }
            .disabled(focusedPane.folderURL == nil)
        Divider()
        Button("Open Folder…") { focusedPane.chooseFolder() }
    }

    private var searchField: some View {
        // Bind directly to the focused pane's query so the field reflects
        // (and edits) the per-pane filter state. Switching focus repoints
        // the binding to the newly-focused pane's value.
        let queryBinding = Binding<String>(
            get: { focusedPane.searchQuery },
            set: { focusedPane.searchQuery = $0 }
        )
        let isEmpty = !focusedPane.isFiltering
        let showField = searchActive || !isEmpty

        return Group {
            if showField {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.labelTertiary)
                    TextField("Search", text: queryBinding)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.breadcrumb)
                        .foregroundStyle(Theme.Color.label)
                        .frame(maxWidth: .infinity)
                        .focused($searchFocused)
                        .onKeyPress(.escape) {
                            if focusedPane.isFiltering {
                                focusedPane.clearSearch()
                            } else {
                                searchFocused = false
                                searchActive = false
                            }
                            return .handled
                        }
                    if !isEmpty {
                        Button {
                            focusedPane.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.Color.labelTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear")
                    }
                }
            } else {
                Button {
                    searchActive = true
                    DispatchQueue.main.async { searchFocused = true }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Color.labelTertiary)
                        Text("Search")
                            .font(Theme.Font.breadcrumb)
                            .foregroundStyle(Theme.Color.labelTertiary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 160, height: 22)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(searchFocused ? Theme.Color.accent : Theme.Color.separator,
                              lineWidth: searchFocused ? 1 : 0.5)
        )
        .onChange(of: searchFocused) { _, focused in
            // When the user tabs/clicks away from an empty field, drop back
            // to the static placeholder so the next session starts inert.
            if !focused && focusedPane.searchQuery.isEmpty {
                searchActive = false
            }
        }
        .help("Search this folder (⌘F)")
    }

    private var layoutSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(PaneLayout.allCases) { paneLayout in
                Button {
                    layout = paneLayout
                } label: {
                    Image(systemName: paneLayout.symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(layout == paneLayout ? Theme.Color.label : Theme.Color.labelSecondary)
                        .frame(width: 26, height: 19)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5)
                                .fill(layout == paneLayout ? Color.white.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(paneLayout.help)
            }
        }
        .padding(1.5)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
    }

    // Toolbar nav buttons: a comfortable 30×28 hit target with a subtle
    // hover background so the click area is obvious. Disabled state dims
    // the icon and skips the hover affordance.
    private struct ToolbarIconButton: View {
        let symbol: String
        let help: String
        let action: () -> Void

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.labelSecondary)
                    .opacity(isEnabled ? 1 : 0.35)
                    .frame(width: 30, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isEnabled && isHovering
                                  ? Color.white.opacity(0.08)
                                  : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(help)
        }
    }

    // MARK: Pane grid

    @ViewBuilder
    private var paneGrid: some View {
        switch layout {
        case .one:
            paneView(0)
        case .twoH:
            HStack(spacing: 0) {
                paneView(0)
                Divider().background(Theme.Color.separator)
                paneView(1)
            }
        case .twoV:
            VStack(spacing: 0) {
                paneView(0)
                Divider().background(Theme.Color.separator)
                paneView(1)
            }
        case .three:
            HStack(spacing: 0) {
                paneView(0)
                Divider().background(Theme.Color.separator)
                VStack(spacing: 0) {
                    paneView(1)
                    Divider().background(Theme.Color.separator)
                    paneView(2)
                }
            }
        case .four:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    paneView(0)
                    Divider().background(Theme.Color.separator)
                    paneView(1)
                }
                Divider().background(Theme.Color.separator)
                HStack(spacing: 0) {
                    paneView(2)
                    Divider().background(Theme.Color.separator)
                    paneView(3)
                }
            }
        }
    }

    private func paneView(_ index: Int) -> some View {
        BrowserPaneView(
            index: index,
            paneVM: paneVM(at: index),
            isFocused: focusedPaneIndex == index
        ) {
            focusedPaneIndex = index
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Global status bar

    private var globalStatusBar: some View {
        let totalCount = focusedPane.entries.count
        let visibleCount = focusedPane.visibleEntries.count
        let selectedCount = focusedPane.selection.count
        // VM-memoized — see `FolderBrowserViewModel.selectedSize`. Avoids the
        // O(selection) compactMap/reduce on every status-bar re-render.
        let selectedSize = focusedPane.selectedSize

        return HStack(spacing: 8) {
            if selectedCount > 0 {
                Text("\(selectedCount) selected")
                    .foregroundStyle(Theme.Color.label)
                Text("·").foregroundStyle(Theme.Color.labelTertiary)
                Text(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))
                    .foregroundStyle(Theme.Color.labelSecondary)
            } else if focusedPane.isFiltering {
                if focusedPane.isSearching {
                    Text("Searching\u{2026}")
                        .foregroundStyle(Theme.Color.labelSecondary)
                } else {
                    Text("\(visibleCount) match\(visibleCount == 1 ? "" : "es")")
                        .foregroundStyle(Theme.Color.labelSecondary)
                }
            } else if totalCount > 0 {
                Text("\(totalCount) item\(totalCount == 1 ? "" : "s")")
                    .foregroundStyle(Theme.Color.labelSecondary)
            }

            Spacer()

            if focusedPane.searchReadErrors > 0 {
                Text("Search incomplete: \(focusedPane.searchReadErrors) read error(s)")
                    .foregroundStyle(.orange)
            }
            if focusedPane.includeHidden {
                Text("Hidden visible").foregroundStyle(Theme.Color.labelSecondary)
                Text("·").foregroundStyle(Theme.Color.labelTertiary)
            }

            if let free = freeSpaceCache {
                Text(free).foregroundStyle(Theme.Color.labelSecondary)
            }
        }
        .font(Theme.Font.secondary)
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.statusBarHeight)
        .background(Theme.Color.statusBarBg)
        // Refresh the cached free-space number only when the focused folder
        // moves (possibly onto another volume) or the filesystem changes —
        // never per render. `freeSpaceString()` used to stat the volume on
        // every body pass, which is synchronous disk I/O on the main actor.
        .onAppear { refreshFreeSpace() }
        .onChange(of: focusedPane.folderURL) { _, _ in refreshFreeSpace() }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirFileSystemChanged)) { _ in
            refreshFreeSpace()
        }
    }

    /// Recompute the cached free-space string for the focused volume. Cheap
    /// enough to run on the triggering events (folder change, fs change); the
    /// win is *not* running it on every status-bar re-render.
    @MainActor
    private func refreshFreeSpace() {
        let url = focusedPane.folderURL ?? FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage
        else {
            freeSpaceCache = nil
            return
        }
        freeSpaceCache = "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) free"
    }

    // MARK: Helpers

    /// The currently-focused pane's tab list. Use this for tab-list operations
    /// (new tab, close, reopen, switch). For tab-content actions like
    /// navigation or selection, prefer `focusedPane` so the call routes to
    /// the active tab inside the pane.
    private var focusedPaneVM: PaneTabsViewModel { paneVM(at: focusedPaneIndex) }

    /// The active tab inside the focused pane. Compatibility shim: every
    /// pre-tabs call site (`focusedPane.openFolder`, `focusedPane.goBack`,
    /// `focusedPane.searchQuery`, …) keeps working unchanged because what
    /// "the pane" used to mean is now "the active tab of the pane."
    private var focusedPane: FolderBrowserViewModel { focusedPaneVM.activeTab }

    private func paneVM(at index: Int) -> PaneTabsViewModel {
        switch index {
        case 0: pane0
        case 1: pane1
        case 2: pane2
        default: pane3
        }
    }
}

// MARK: - Body modifier chunks
//
// SwiftUI's view-builder type checker collapses on a body with ~25 chained
// modifiers, so the wiring is split into focused `ViewModifier` chunks. Each
// modifier owns one slice of the cross-cutting concern (save triggers,
// navigation notifications, tab notifications, app lifecycle), and the body
// applies them in sequence. The split is purely a compile-time concession;
// the runtime semantics match the original flat chain.

private struct SaveTriggers: ViewModifier {
    @ObservedObject var pane0: PaneTabsViewModel
    @ObservedObject var pane1: PaneTabsViewModel
    @ObservedObject var pane2: PaneTabsViewModel
    @ObservedObject var pane3: PaneTabsViewModel
    @ObservedObject var sidebar: SidebarViewModel
    @Binding var layout: PaneLayout
    @Binding var focusedPaneIndex: Int
    let scheduleSave: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: layout) { _, newLayout in
                if focusedPaneIndex >= newLayout.paneCount {
                    focusedPaneIndex = 0
                }
                scheduleSave()
            }
            .onChange(of: focusedPaneIndex) { _, _ in scheduleSave() }
            .onReceive(pane0.objectWillChange.persistedChanges) { _ in scheduleSave() }
            .onReceive(pane1.objectWillChange.persistedChanges) { _ in scheduleSave() }
            .onReceive(pane2.objectWillChange.persistedChanges) { _ in scheduleSave() }
            .onReceive(pane3.objectWillChange.persistedChanges) { _ in scheduleSave() }
            .onReceive(sidebar.objectWillChange.persistedChanges) { _ in scheduleSave() }
    }
}

private struct NavigationNotifications: ViewModifier {
    let focusedPane: FolderBrowserViewModel
    @Binding var searchActive: Bool
    var searchFocused: FocusState<Bool>.Binding
    @ObservedObject var sidebar: SidebarViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .mqdirCommand)) { note in
                guard let command = AppCommand.from(note) else { return }
                switch command {
                case .openFolder:
                    focusedPane.chooseFolder()
                case .openSelected:
                    focusedPane.openSelected()
                case .revealSelected:
                    focusedPane.revealSelected()
                case .reload:
                    focusedPane.reload()
                case .parentFolder:
                    focusedPane.openParentFolder()
                case .toggleHiddenFiles:
                    focusedPane.toggleHiddenFiles()
                case .goBack:
                    focusedPane.goBack()
                case .goForward:
                    focusedPane.goForward()
                case .focusSearch:
                    searchActive = true
                    // Defer focus until after the conditional TextField has
                    // been installed by the body re-render triggered above.
                    DispatchQueue.main.async { searchFocused.wrappedValue = true }
                case .addCurrentFolderToFavorites:
                    if let url = focusedPane.folderURL {
                        sidebar.add(url: url)
                    }
                case .togglePreview:
                    focusedPane.previewVisible.toggle()
                case .setViewModeList:
                    focusedPane.viewMode = .list
                case .setViewModeTree:
                    focusedPane.viewMode = .tree
                // Edit / tab / pane-focus commands belong to the other
                // modifiers in this chain; ignore them here.
                default:
                    break
                }
            }
    }
}

/// Eagle/Finder-parity file-selection actions (Open with Default App,
/// Duplicate, Copy File Path / Folder Path / Name) — split into its
/// own modifier for the same SwiftUI type-checker reason as
/// `EditMenuNotifications`.
private struct EditFileActionsNotifications: ViewModifier {
    let focusedPane: FolderBrowserViewModel
    /// See `EditMenuNotifications.normalizeHangul` — wired so the ⌘D
    /// duplicate path also normalises the resulting NFD name when on.
    let normalizeHangul: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .mqdirCommand)) { note in
                guard let command = AppCommand.from(note) else { return }
                switch command {
                case .openWithDefaultApp:
                    focusedPane.openSelectedWithDefaultApp()
                case .duplicate:
                    focusedPane.duplicateSelection(normalizeHangul: normalizeHangul)
                case .copyFilePaths:
                    focusedPane.copySelectedFilePathsToPasteboard()
                case .copyFolderPath:
                    focusedPane.copyCurrentFolderPath()
                case .copyName:
                    focusedPane.copySelectedNamesToPasteboard()
                case .rename:
                    focusedPane.beginRenameForActiveSelection()
                default:
                    break
                }
            }
    }
}

/// Edit-menu file actions (Select All / Copy / Paste / Delete) split
/// out of `NavigationNotifications` because adding more `.onReceive`
/// modifiers in one chain pushes the SwiftUI type-checker over its
/// expression-complexity ceiling. One small modifier per concern keeps
/// every `body` cheap to compile.
private struct EditMenuNotifications: ViewModifier {
    let focusedPane: FolderBrowserViewModel
    /// Live "normalise Hangul on drag out" setting, captured where this
    /// modifier is built (in `MainWindowView.body`, which owns the
    /// workspace) so the ⌘V paste path can normalise pasted-in NFD names.
    let normalizeHangul: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .mqdirCommand)) { note in
                guard let command = AppCommand.from(note) else { return }
                switch command {
                case .selectAll:
                    focusedPane.selectAll()
                case .copy:
                    focusedPane.copySelectionToPasteboard()
                case .cut:
                    focusedPane.cutSelectionToPasteboard()
                case .paste:
                    focusedPane.pasteFromPasteboard(normalizeHangul: normalizeHangul)
                case .delete:
                    focusedPane.moveSelectionToTrash()
                case .permanentDelete:
                    focusedPane.permanentlyDeleteSelection()
                default:
                    break
                }
            }
    }
}

/// ⌥⌘1–4 → focus pane index 0–3. Indices outside the active layout's
/// pane count are silently ignored so a ⌥⌘4 in single-pane layout is a
/// no-op rather than a hidden focus jump into a stashed pane.
private struct PaneFocusNotifications: ViewModifier {
    let layout: PaneLayout
    @Binding var focusedPaneIndex: Int

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .mqdirCommand)) { note in
                guard case let .focusPane(index) = AppCommand.from(note) else { return }
                guard index >= 0, index < layout.paneCount else { return }
                focusedPaneIndex = index
            }
    }
}

private struct TabNotifications: ViewModifier {
    @ObservedObject var focusedPaneVM: PaneTabsViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .mqdirCommand)) { note in
                guard let command = AppCommand.from(note) else { return }
                switch command {
                case .newTab:
                    focusedPaneVM.newTab()
                case .closeTab:
                    focusedPaneVM.closeActive()
                case .reopenClosedTab:
                    focusedPaneVM.reopenClosed()
                case .nextTab:
                    focusedPaneVM.nextTab()
                case .previousTab:
                    focusedPaneVM.prevTab()
                case let .selectTab(index):
                    focusedPaneVM.selectTab(at: index)
                // ⌘-click on a folder in tree/list view → new tab pointing at
                // it. Always lands in the *focused* pane so the user gets the
                // detail view next to their tree, not in some other pane.
                case let .openURLInNewTab(url):
                    focusedPaneVM.newTab(folderURL: url)
                default:
                    break
                }
            }
    }
}

private struct GlobalNotifications: ViewModifier {
    let allPanes: [PaneTabsViewModel]
    let saveSynchronously: () -> Void

    func body(content: Content) -> some View {
        content
            // FSEvents lands in M3 per plan §3 — until then drag/drop posts
            // an explicit "I changed the filesystem" notification and every
            // open tab in every pane refetches its folder.
            .onReceive(NotificationCenter.default.publisher(for: .mqdirFileSystemChanged)) { notification in
                let folders = FileSystemChange.folders(in: notification)
                for paneVM in allPanes {
                    for tab in paneVM.tabs where tab.searchRoots.contains(where: {
                        FileChangeScope.affects(root: $0, changedFolders: folders, recursive: tab.isFiltering || tab.viewMode == .tree)
                    }) {
                        tab.reload()
                    }
                }
            }
            // Synchronous save on app termination (debounce would be cancelled
            // by the runloop tearing down). Posted by mqdirApp.
            .onReceive(NotificationCenter.default.publisher(for: .mqdirAppWillTerminate)) { _ in
                saveSynchronously()
            }
    }
}

#Preview {
    MainWindowView(
        workspace: WorkspaceManager(),
        updateManager: UpdateManager(),
        repoCallout: RepoCalloutController()
    )
        .frame(width: 1100, height: 700)
}
