import AppKit
import CoreGraphics
import Foundation

// `PaneColumnWidths` and `FileEntrySortKey` now live in `Sources/Core/` so
// that persisted pane state is fully testable from `swift test`. They are
// re-exported by being members of the same Xcode module.

@MainActor
final class FolderBrowserViewModel: ObservableObject, Identifiable {
    /// Stable identity for SwiftUI's diffing — `ObjectIdentifier` is unique
    /// per instance and free, since the VM is always class-bound. The tab
    /// bar uses this to keep its `ForEach` rows tied to the right VM across
    /// reorders and closes.
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    @Published private(set) var folderURL: URL?
    @Published private(set) var entries: [FileEntry] = [] {
        didSet {
            // Root cache ownership lives here, not in the tree view: the
            // root's `treeChildren` entry tracks `entries` 1:1 (folders-first
            // via the shared helper) on every assignment, so tree mode renders
            // correctly even when `TreeFileListView` isn't alive to mirror it.
            // Cheap — an array copy. `reload()` clears `treeChildren` *after*
            // setting `entries`, so it re-populates the root itself (see
            // `refreshTreeChildren`).
            if let root = folderURL {
                treeChildren[root.path] = FileEntry.treeOrdered(entries)
            }
            rebuildEntriesIndex()
            invalidateRowCaches()
            // Status-bar / sidebar derived values read off `entries`.
            cachedTagSummaries = nil
            cachedSelectedSize = nil
        }
    }
    @Published var selection: Set<FileEntry.ID> = [] {
        didSet { cachedSelectedSize = nil }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var includeHidden = false {
        didSet {
            reload()
        }
    }
    /// Per-pane recursive search over `folderURL`. Case-insensitive substring
    /// match on entry name. Empties on folder navigation. Each keystroke
    /// schedules a debounced background walk that populates `searchResults`.
    /// Not persisted — transient view state.
    @Published var searchQuery: String = "" {
        didSet {
            // `isFiltering` flips with the first/last character, swapping
            // which axis `visibleEntries` returns — invalidate the list-mode
            // row cache so a keypress right after typing doesn't scan a stale
            // index. The recursive walk itself is scheduled below.
            if oldValue.isEmpty != searchQuery.isEmpty { invalidateRowCaches() }
            // Search and tag filter are mutually exclusive — they each swap
            // which axis `visibleEntries` returns, so letting both be active
            // would render an ambiguous list. Typing a query clears any tag
            // filter. The `!isEmpty` guard means *clearing* the query (e.g.
            // on folder navigation) doesn't stomp a tag filter the user
            // hasn't touched. Setting `tagFilter` clears `searchQuery` in its
            // own setter, so the two never recurse (this branch only fires
            // for a non-empty query, which the tag-filter path never writes).
            if !searchQuery.isEmpty, tagFilter != nil { tagFilter = nil }
            scheduleSearch()
        }
    }
    /// Per-pane current-folder tag filter. When non-nil, `visibleEntries`
    /// shows only entries whose `tagNames` contain this name. Mutually
    /// exclusive with `searchQuery` (see that setter) — set by clicking a
    /// tag in the sidebar's Tags section, cleared by clicking the same tag
    /// again or by the active-filter chip's ✕. Not persisted: transient
    /// view state, like `searchQuery`.
    ///
    /// Tag names compare with Swift's `String ==`, which is Unicode
    /// canonical-equivalence aware (NFC vs NFD), so a "업무" written by Finder
    /// in one normalisation form still matches the sidebar summary's name in
    /// another — the same property the tag-colour index-pairing relies on.
    ///
    /// Scope is current-folder LIST filtering only — it filters `entries`,
    /// not a recursive walk. Recursive tag search (find every tagged file
    /// under the root) is deliberately future work; current-folder filtering
    /// is the simplest correct scope and mirrors how `searchResults` only
    /// ever drives the flat list.
    @Published var tagFilter: String? {
        didSet {
            guard oldValue != tagFilter else { return }
            // Swapping the visible axis — drop the list-mode row cache so the
            // next nav keypress walks the filtered set, mirroring searchQuery.
            invalidateRowCaches()
            // Mutual exclusion: activating a tag filter clears any live
            // search. Guarded on non-nil so clearing the filter doesn't wipe
            // a query, and so this never recurses with the searchQuery setter.
            if tagFilter != nil {
                projectSearchRoots = nil
                projectSearchWatchers.removeAll()
                searchFilter = .init()
                searchQuery = ""
            }
        }
    }
    @Published var searchFilter = FileSearchFilter() {
        didSet {
            guard oldValue != searchFilter else { return }
            if searchFilter.isActive { tagFilter = nil }
            scheduleSearch()
        }
    }
    @Published private(set) var searchReadErrors = 0
    private(set) var projectSearchRoots: [URL]?
    private var projectSearchWatchers: [DirectoryWatcher] = []
    private var searchEntriesByID: [FileEntry.ID: FileEntry] = [:]

    func clearSearch() {
        projectSearchRoots = nil
        projectSearchWatchers.removeAll()
        searchFilter = .init()
        searchQuery = ""
    }

    func applySearch(_ search: SavedFileSearch, projectRoots: [URL]) {
        let roots = Self.minimalSearchRoots(projectRoots)
        if search.projectScope, folderURL == nil, let first = roots.first { openFolder(first) }
        projectSearchRoots = search.projectScope ? roots : nil
        projectSearchWatchers.removeAll()
        if watchesDirectories {
            projectSearchWatchers = (projectSearchRoots ?? []).filter { $0 != folderURL }.map { url in
                DirectoryWatcher(url: url) { [weak self] in
                    Task { @MainActor [weak self] in self?.reload() }
                }
            }
        }
        searchFilter = search.filter
        searchQuery = search.query
    }

    static func minimalSearchRoots(_ urls: [URL]) -> [URL] {
        var roots: [URL] = []
        for url in urls {
            let parts = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            if roots.contains(where: { parts.starts(with: $0.resolvingSymlinksInPath().standardizedFileURL.pathComponents) }) { continue }
            roots.removeAll { $0.resolvingSymlinksInPath().standardizedFileURL.pathComponents.starts(with: parts) }
            roots.append(url)
        }
        return roots
    }

    var searchRoots: [URL] { projectSearchRoots ?? [folderURL].compactMap { $0 } }

    /// Recursive matches for the active `searchQuery`. Empty when not
    /// filtering, or while the first results of a fresh query are still
    /// being gathered.
    @Published private(set) var searchResults: [FileEntry] = [] {
        didSet { invalidateRowCaches(); cachedSelectedSize = nil }
    }
    /// True between a non-empty `searchQuery` arriving and the resulting
    /// recursive walk completing. Drives the spinner / "Searching…" hint.
    @Published private(set) var isSearching: Bool = false
    /// On-demand directory sizes, keyed by `FileEntry.ID` (the entry's URL).
    /// `enumerateDirectory` leaves folders with `size == nil` (sizing every
    /// folder on every listing would be ruinous), so the size column shows
    /// "—" for directories until the user invokes "Calculate Size"; the
    /// walk's result lands here and the column repaints. Invalidating the
    /// selected-size cache on every assignment keeps the status-bar total in
    /// sync when a folder's size resolves.
    @Published private(set) var computedDirectorySizes: [FileEntry.ID: Int64] = [:] {
        didSet { cachedSelectedSize = nil }
    }
    /// Directories whose size walk is currently in flight. The size cell
    /// renders "…" for these so the user sees the calculation is running
    /// rather than a stale "—".
    @Published private(set) var computingSizeIDs: Set<FileEntry.ID> = []
    /// Bumped on every navigation / reload so a size walk that outlived its
    /// folder can detect it's stale and skip publishing. A stale write keyed
    /// by URL-ID is harmless anyway (the entry is gone, so nothing renders
    /// it), but dropping it keeps `computedDirectorySizes` from accreting
    /// dead URLs across a long browsing session.
    private var sizeWalkGeneration = 0
    @Published private(set) var sortKey: FileEntrySortKey = .name
    @Published private(set) var sortAscending = true
    /// When true, directories sort ahead of files within the same key.
    /// Per-tab so a user can keep folders pinned in one pane while
    /// reading a flat date-sorted list in another.
    @Published private(set) var foldersOnTop = true
    @Published var columnWidths = PaneColumnWidths()
    /// FileEntry.id of the row currently in inline-rename mode (its
    /// label is showing a TextField instead of static text). nil means
    /// no row is being renamed. Driven by the Edit menu's Rename
    /// action, the row context menu, or the future double-click-to-
    /// rename gesture.
    @Published var renamingEntryID: FileEntry.ID?
    /// Live text the rename TextField is bound to. Cleared together
    /// with `renamingEntryID` on commit / cancel.
    @Published var renameDraft: String = ""
    /// Per-tab view mode. Switching to `.tree` triggers a lazy enumeration
    /// of the root, then of any folder the user expands.
    @Published var viewMode: PaneViewMode = .list
    /// Whether the right-side preview panel is shown for this tab.
    @Published var previewVisible: Bool = false
    @Published var listScrollID: URL?
    @Published var treeScrollID: URL?
    private var pendingListScrollPath: String?
    private var pendingTreeScrollPath: String?
    /// Set of expanded directory paths in tree mode. Stored as paths so
    /// it survives serialization without bookmark plumbing — losing access
    /// to a path just collapses that node, never breaks the view.
    @Published var expandedPaths: Set<String> = [] {
        didSet { invalidateRowCaches() }
    }
    /// Cached children per directory path for tree mode. Populated on
    /// expand, evicted on `reload()`. Doesn't bloat memory in normal use
    /// because the user only expands what they actively browse. The
    /// setter is open so `TreeFileListView` can mirror the root entries
    /// into the cache without a dedicated method on the VM.
    @Published var treeChildren: [String: [FileEntry]] = [:] {
        didSet {
            rebuildEntriesIndex()
            invalidateRowCaches()
            // Tree-mode selections live in `treeChildren`, so their sizes do
            // too — a subtree refresh can change the selected-size total.
            cachedSelectedSize = nil
        }
    }
    @Published private(set) var backStack: [NavigationFrame] = []
    @Published private(set) var forwardStack: [NavigationFrame] = []
    @Published private(set) var selectionAnchor: FileEntry.ID?
    /// Trailing edge of the active range-selection — Finder calls this
    /// the "cursor". Shift+arrow / Shift-click advance the cursor while
    /// the anchor stays put, so `selection = range[anchor, cursor]`.
    /// Splitting it from `selectionAnchor` is what makes successive
    /// Shift+↓ presses *grow* the selection instead of capping at two
    /// rows (`currentIdx` would otherwise stay glued to the anchor).
    @Published private(set) var selectionCursor: FileEntry.ID?

    /// One entry in the back/forward history. Carries the folder URL
    /// the user was on AND the selection they had at the time, so
    /// `goBack()`/`goForward()` restores both. The selection lives as
    /// `[String]` paths (not `Set<FileEntry.ID>`) because IDs change
    /// across re-enumerations — paths survive a fresh `reload()` via
    /// the same `pendingRestoredSelection` matching the launch
    /// restore uses.
    struct NavigationFrame: Equatable, Sendable {
        let url: URL
        let selectionPaths: [String]
    }

    /// Restored selection paths waiting to be matched against the next
    /// successful `entries` enumeration. Cleared after the match runs.
    private var pendingRestoredSelection: [String] = []

    /// Bookmark for the currently-open `folderURL`, refreshed on each
    /// `openFolder` so a `tabSnapshot()` returns durable state without
    /// re-creating bookmarks at save time.
    private var currentBookmark: Data?

    /// True when this VM holds a `startAccessingSecurityScopedResource()`
    /// claim that must be balanced before changing folders.
    private var hasSecurityScopeAccess = false

    /// Non-isolated mirror of the URL we hold a security-scope claim on,
    /// so `deinit` (which can't touch main-actor state under strict
    /// concurrency) can still balance it. Updated whenever the claim does.
    private nonisolated(unsafe) var scopedURL: URL?

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    typealias DirectoryLoader = @Sendable (URL, Bool, @Sendable () -> Bool) throws -> [FileEntry]
    private var directoryLoader: DirectoryLoader = { url, hidden, cancelled in
        try FileSystemService().enumerateDirectory(at: url, includingHidden: hidden, isCancelled: cancelled)
    }
    private let treeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "mqdir.tree-loads"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var treeLoadTokens: [String: ProcessRunner.Cancellation] = [:]
    @Published private(set) var loadingTreePaths: Set<String> = []
    @Published private(set) var treeLoadErrors: [String: String] = [:]
    private var pendingTreeReveal: FileEntry.ID?

    private var loadTask: Task<Void, Never>?
    private var loadCancelToken: ProcessRunner.Cancellation?
    private var sizeCancelToken: ProcessRunner.Cancellation?
    private var searchTask: Task<Void, Never>?
    /// Token handed to the in-flight enumerator so we can stop it early when
    /// a newer query supersedes it. Detached tasks don't inherit cancellation,
    /// so we propagate via a Sendable flag instead of relying on Task.isCancelled.
    private var searchCancelToken: SearchCancelToken?

    /// FSEvents-backed watcher for the active `folderURL`. Recreated
    /// whenever the user navigates; the watcher's own `deinit` stops
    /// the underlying stream, so dropping the reference is enough to
    /// tear it down. ARC handles the final release on VM deinit.
    private var directoryWatcher: DirectoryWatcher?
    private var watchesDirectories = true

    /// Default initializer — fresh, empty pane (used by previews and the
    /// first launch when no persisted state exists).
    init(watchingDirectories: Bool = true, directoryLoader: DirectoryLoader? = nil) {
        watchesDirectories = watchingDirectories
        if let directoryLoader { self.directoryLoader = directoryLoader }
    }

    /// Restoration initializer — rehydrates a tab from a saved `TabState`.
    /// If the bookmark resolves, opens the folder and queues the saved
    /// selection to be matched against the loaded entries.
    init(state: TabState) {
        self.sortKey = state.sortKey
        self.sortAscending = state.sortAscending
        self.foldersOnTop = state.foldersOnTop
        self.includeHidden = state.includeHidden
        self.columnWidths = state.columnWidths
        self.pendingRestoredSelection = state.selectedURLPaths
        self.viewMode = state.viewMode
        self.expandedPaths = Set(state.expandedPaths)
        self.previewVisible = state.previewVisible
        self.pendingListScrollPath = state.listScrollPath
        self.pendingTreeScrollPath = state.treeScrollPath

        if let bookmark = state.folderBookmark,
           let resolved = PersistenceService.resolveBookmark(bookmark) {
            self.currentBookmark = bookmark
            self.pendingListScrollPath = state.listScrollPath.flatMap { FileSystemService.restoredPath($0, under: resolved) }
            self.pendingTreeScrollPath = state.treeScrollPath.flatMap { FileSystemService.restoredPath($0, under: resolved) }
            self.expandedPaths = Set(state.expandedPaths.compactMap { FileSystemService.restoredPath($0, under: resolved) })
            self.pendingRestoredSelection = state.selectedURLPaths.compactMap { FileSystemService.restoredPath($0, under: resolved) }
            // Sandbox-readiness: claim security scope before any I/O.
            if resolved.startAccessingSecurityScopedResource() {
                self.hasSecurityScopeAccess = true
                self.scopedURL = resolved
            }
            self.folderURL = resolved
            reload()
            updateDirectoryWatcher()
            // reload() schedules expanded children after the root is ready.

        }
    }

    deinit {
        loadCancelToken?.cancel()
        sizeCancelToken?.cancel()
        searchCancelToken?.cancel()
        loadTask?.cancel()
        searchTask?.cancel()
        for token in treeLoadTokens.values { token.cancel() }
        // Balance any outstanding security-scope claim. `scopedURL` is the
        // nonisolated mirror — deinit can't touch main-actor state, so we
        // only release through this side-channel pointer.
        if let url = scopedURL {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Snapshot the live tab state for serialization.
    func tabSnapshot() -> TabState {
        TabState(
            folderBookmark: currentBookmark,
            sortKey: sortKey,
            sortAscending: sortAscending,
            includeHidden: includeHidden,
            columnWidths: columnWidths,
            selectedURLPaths: selectedURLs.map(\.path),
            viewMode: viewMode,
            expandedPaths: Array(expandedPaths),
            previewVisible: previewVisible,
            foldersOnTop: foldersOnTop,
            listScrollPath: listScrollID?.path ?? pendingListScrollPath,
            treeScrollPath: treeScrollID?.path ?? pendingTreeScrollPath
        )
    }

    // MARK: Tree mode

    /// Toggle expansion for a directory in tree mode. Lazy-loads children
    /// on first expand. On collapse, evicts this path's cached children AND
    /// every descendant path's children: a collapsed subtree is invisible, so
    /// holding its (potentially deep) listing just bloats `treeChildren` and
    /// makes every later `rebuildEntriesIndex` walk more rows than are on
    /// screen. The "instant re-expand" we'd keep is marginal next to that
    /// unbounded-growth cost — re-expanding simply re-enumerates one folder.
    /// The root path is never a collapsible node here, so it's untouched.
    func toggleExpanded(_ url: URL) {
        let path = url.path
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
            evictCachedSubtree(under: path)
        } else {
            expandedPaths.insert(path)
            if treeChildren[path] == nil {
                loadChildren(for: url)
            }
        }
    }

    /// Drop `path`'s cached children plus every descendant path's children
    /// from `treeChildren`. Descendants are matched by the standard
    /// `"<path>/"` prefix test (the same shape the drop/self-drop guards use).
    /// Skips the early-return-friendly no-op when nothing matches so an
    /// unrelated collapse doesn't dirty the cache.
    private func evictCachedSubtree(under path: String) {
        let descendantPrefix = path + "/"
        for key in treeLoadTokens.keys.filter({ $0 == path || $0.hasPrefix(descendantPrefix) }) {
            treeLoadTokens.removeValue(forKey: key)?.cancel()
            loadingTreePaths.remove(key)
        }
        treeLoadErrors = treeLoadErrors.filter { $0.key != path && !$0.key.hasPrefix(descendantPrefix) }
        let doomed = treeChildren.keys.filter {
            $0 == path || $0.hasPrefix(descendantPrefix)
        }
        guard !doomed.isEmpty else { return }
        // Mutate a local copy and assign once so the `treeChildren` `didSet`
        // (rebuildEntriesIndex + cache invalidation) fires a single time, not
        // once per removed key.
        var pruned = treeChildren
        for key in doomed {
            pruned.removeValue(forKey: key)
        }
        treeChildren = pruned
    }

    func isExpanded(_ url: URL) -> Bool {
        expandedPaths.contains(url.path)
    }

    /// Row the tree view should scroll into view on its next render. Set by
    /// `revealInTree`, consumed (and cleared) by `TreeFileListView` via an
    /// `onChange` that calls `proxy.scrollTo`. A published signal rather than
    /// a direct proxy call because the VM has no `ScrollViewProxy` — the
    /// proxy lives inside the tree's `ScrollViewReader`.
    @Published var pendingRevealTarget: FileEntry.ID?

    /// "Reveal in Tree": surface `entry` — typically a deep recursive-search
    /// hit — in tree mode with every ancestor folder between the root and the
    /// entry expanded, the entry selected, and a scroll-into-view queued.
    ///
    /// Steps, in order:
    /// 1. Clear both filters so the tree shows the real hierarchy, not a
    ///    filtered list (search results / tag filter only drive list mode).
    /// 2. Switch to tree mode.
    /// 3. Expand each ancestor top-down (`FileSystemService.ancestorFolders`
    ///    gives the root-relative chain, leaf excluded). Each expand inserts
    ///    the path into `expandedPaths` and loads that folder's children so
    ///    `treeChildren` is populated for the row that needs to render.
    /// 4. Select the entry and queue it as the scroll target.
    ///
    /// Harmless for a direct child of the root: the ancestor chain is empty,
    /// so it just selects + scrolls without expanding anything.
    func revealInTree(_ entry: FileEntry) {
        guard let root = folderURL else { return }
        // Filters drive list mode only; clear them so the tree renders the
        // full hierarchy the reveal walks into.
        searchQuery = ""
        tagFilter = nil
        viewMode = .tree

        for ancestor in FileSystemService.ancestorFolders(from: root, to: entry.url) {
            let path = ancestor.path
            if !expandedPaths.contains(path) {
                expandedPaths.insert(path)
            }
            // Load children even if the path was already expanded but never
            // populated (e.g. a stale expandedPaths entry from restore), so
            // the ancestor's subtree is present for the next level to render.
            if treeChildren[path] == nil {
                loadChildren(for: ancestor)
            }
        }

        replaceSelection(entry.id)
        pendingTreeReveal = entry.id
        publishTreeRevealIfReady()
    }

    /// Two background workers per tab; collapse/reload cancels requests and
    /// a token identity prevents old results from repopulating a new tree.
    private func loadChildren(for url: URL) {
        let path = url.path
        guard treeLoadTokens[path] == nil, let currentRoot = folderURL,
              url.standardizedFileURL.pathComponents.count > currentRoot.standardizedFileURL.pathComponents.count,
              url.standardizedFileURL.pathComponents.starts(with: currentRoot.standardizedFileURL.pathComponents),
              FileSystemService.ancestorFolders(from: currentRoot, to: url)
                .allSatisfy({ expandedPaths.contains($0.path) }) else { return }
        let token = ProcessRunner.Cancellation()
        treeLoadTokens[path] = token
        loadingTreePaths.insert(path)
        treeLoadErrors[path] = nil
        let root = folderURL
        let hidden = includeHidden
        let loader = directoryLoader
        let queue = treeQueue
        Task { [weak self] in
            let result: Result<[FileEntry], Error> = await withCheckedContinuation { continuation in
                queue.addOperation {
                    continuation.resume(returning: Result {
                        if token.isCancelled { throw CancellationError() }
                        return try loader(url, hidden, { token.isCancelled })
                    })
                }
            }
            guard let self, !token.isCancelled, self.folderURL == root,
                  self.treeLoadTokens[path] === token, self.expandedPaths.contains(path) else { return }
            self.treeLoadTokens[path] = nil
            self.loadingTreePaths.remove(path)
            switch result {
            case .success(let entries):
                self.treeChildren[path] = FileEntrySorter.sorted(entries, by: self.sortKey,
                    ascending: self.sortAscending, foldersOnTop: self.foldersOnTop)
            case .failure(let error):
                self.treeLoadErrors[path] = error.localizedDescription
            }
            self.publishTreeRevealIfReady()
            self.restoreTreeSelectionIfReady()
        }
    }

    func retryTreeChildren(_ url: URL) {
        guard expandedPaths.contains(url.path) else { return }
        loadChildren(for: url)
    }

    private func restoreTreeSelectionIfReady() {
        guard loadingTreePaths.isEmpty, viewMode == .tree, searchQuery.isEmpty else { return }
        if let path = pendingTreeScrollPath {
            treeScrollID = entriesByID.values.first(where: { $0.url.path == path })?.id
            pendingTreeScrollPath = nil
        }
        let savedPaths = Set(pendingRestoredSelection)
        selection.formUnion(entriesByID.values.filter { savedPaths.contains($0.url.path) }.map(\.id))
        pendingRestoredSelection = []
        selection.formIntersection(Set(entriesByID.keys))
    }

    private func publishTreeRevealIfReady() {
        guard let target = pendingTreeReveal, visibleTreeEntries.contains(where: { $0.id == target }) else { return }
        pendingTreeReveal = nil
        pendingRevealTarget = target
    }

    /// Discard cached subtree contents so a fresh `reload()` of the root
    /// also refreshes any expanded children. Re-issues child loads for the
    /// folders that were expanded, which keeps their state visible without
    /// requiring the user to toggle them again.
    func refreshTreeChildren() {
        let stillExpanded = expandedPaths
        for token in treeLoadTokens.values { token.cancel() }
        treeLoadTokens.removeAll()
        loadingTreePaths.removeAll()
        treeLoadErrors.removeAll()
        treeChildren.removeAll()
        // `removeAll()` drops the root entry the `entries` didSet just set;
        // restore it so tree mode keeps a fresh root listing after a reload.
        if let root = folderURL {
            treeChildren[root.path] = FileEntry.treeOrdered(entries)
        }
        for path in stillExpanded {
            loadChildren(for: URL(fileURLWithPath: path))
        }
        restoreTreeSelectionIfReady()
    }

    var selectedEntry: FileEntry? {
        guard let selectedID = selection.first else {
            return nil
        }
        return findEntry(id: selectedID)
    }

    /// O(1) lookup index over `entries` plus every cached `treeChildren`
    /// subtree. Rebuilt by `rebuildEntriesIndex()` on every mutation of
    /// either source. The previous linear scan turned bulk-selection
    /// (`Cmd+A` on ~1000 entries) into O(M×N) and hung the app.
    private var entriesByID: [FileEntry.ID: FileEntry] = [:]

    /// Lazily-built ordered row sequences, keyed by view mode. Arrow-key nav
    /// (`moveSelection`) and Shift-range (`extendSelection`) previously
    /// rebuilt the full DFS flatten on every ↑/↓ — O(n) work per keypress in
    /// a large tree. These cache the flattened order once; the range math
    /// (now in `mqdirCore.SelectionModel`) walks the cached row IDs. `nil`
    /// means "needs rebuild"; the row sources change only on the same events
    /// that rebuild `entriesByID` (`entries` / `treeChildren` mutations) plus
    /// `expandedPaths` and the filter toggle, so invalidation hooks all of
    /// those.
    private var cachedTreeRows: [FileEntry]?
    private var cachedListRows: [FileEntry]?

    /// Memoized status-bar / sidebar derived values. The global status bar
    /// re-reads `selectedSize` and the sidebar re-reads `tagSummaries` on
    /// every `MainWindowView` body re-render — without these, each render
    /// re-ran an O(selection) size reduce and an O(entries) tag walk. `nil`
    /// means "needs recompute"; invalidated from the `didSet` of the sources
    /// each reads (`selection`/`entries`/`treeChildren` for the size,
    /// `entries` for the tag summaries).
    private var cachedSelectedSize: Int64?
    private var cachedTagSummaries: [TagSummary]?

    /// Drop the lazily-built row order caches. Called from the `didSet` of
    /// every source the flatten/visible-list reads (`entries`,
    /// `treeChildren`, `expandedPaths`, `searchResults`, and the filter
    /// on/off edge of `searchQuery`). The next nav keypress rebuilds on demand.
    private func invalidateRowCaches() {
        cachedTreeRows = nil
        cachedListRows = nil
    }

    /// Look up a `FileEntry` by id across both the flat root listing
    /// (`entries`) and every cached tree subtree (`treeChildren`). Tree
    /// view selections live deep in `treeChildren`, never in
    /// `entries`, so anything that operates on the active selection
    /// (rename, etc.) needs this wider search to avoid silently
    /// no-op'ing in tree mode.
    func findEntry(id: FileEntry.ID) -> FileEntry? {
        if isFiltering, let entry = searchEntriesByID[id] { return entry }
        return entriesByID[id]
    }

    private func rebuildEntriesIndex() {
        var index: [FileEntry.ID: FileEntry] = [:]
        index.reserveCapacity(entries.count)
        for entry in entries {
            index[entry.id] = entry
        }
        for children in treeChildren.values {
            for entry in children {
                index[entry.id] = entry
            }
        }
        entriesByID = index
    }

    /// What the file list should render. Recursive `searchResults` while a
    /// query is active, the tag-filtered subset of `entries` while a tag
    /// filter is active, the canonical `entries` for the current folder
    /// otherwise. Selection IDs always resolve against `entries` (so a
    /// recursive hit clicked into a subfolder navigates fresh).
    ///
    /// Search and tag filter are mutually exclusive (enforced in their
    /// setters), so the order here is unambiguous: at most one branch is
    /// ever non-trivial.
    var visibleEntries: [FileEntry] {
        if isFiltering { return searchResults }
        if let tag = tagFilter {
            // Current-folder filtering only — `entries`, not a recursive
            // walk. `String ==` is NFC/NFD-aware so a tag name stored in one
            // normalisation form still matches the clicked summary's form.
            return entries.filter { $0.tagNames.contains(tag) }
        }
        return entries
    }

    /// True when a current-folder tag filter is narrowing the list. Distinct
    /// from `isFiltering` (search), which drives the recursive-walk UI
    /// (subtitles, "Searching…"). The active-filter chip and item-count
    /// label read this to render the tag affordance without pulling in the
    /// search-specific chrome.
    var isTagFiltering: Bool { tagFilter != nil }

    /// Flat top-to-bottom sequence of every row currently rendered by
    /// `TreeFileListView` (root → expanded children → expanded
    /// grandchildren …). Used by arrow-key navigation so ↑/↓ in tree mode
    /// walks the same visual order the user sees, not just the root level.
    /// Folders-first per level via the shared `FileEntry.treeOrdered`
    /// helper — same ordering rule `TreeFileListView` applies to each
    /// rendered level. Cached — the DFS flatten only rebuilds when a source
    /// the tree reads from changes, not on every keypress.
    var visibleTreeEntries: [FileEntry] {
        if let cached = cachedTreeRows { return cached }
        guard let root = folderURL else {
            cachedTreeRows = []
            return []
        }
        let rootEntries = treeChildren[root.path] ?? entries
        let rows = flattenTree(rootEntries)
        cachedTreeRows = rows
        return rows
    }

    private func flattenTree(_ entries: [FileEntry]) -> [FileEntry] {
        var result: [FileEntry] = []
        for entry in FileEntry.treeOrdered(entries) {
            result.append(entry)
            if entry.isDirectory,
               isExpanded(entry.url),
               let children = treeChildren[entry.url.path] {
                result.append(contentsOf: flattenTree(children))
            }
        }
        return result
    }

    /// Cached version of `visibleEntries` for the nav hot path. Identical
    /// contents to `visibleEntries` but the array is reused across keypresses
    /// instead of re-allocating `searchResults`/`entries`.
    private var cachedVisibleEntries: [FileEntry] {
        if let cached = cachedListRows { return cached }
        let rows = visibleEntries
        cachedListRows = rows
        return rows
    }

    var isFiltering: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || searchFilter.isActive
    }

    var folderDisplayPath: String {
        folderURL?.path(percentEncoded: false) ?? "No folder selected"
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.prompt = "Open"
        panel.message = "Choose a folder to browse in mq-dir."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        openFolder(url)
    }

    /// Navigate to a folder, recording the current location in the back stack
    /// and clearing the forward stack. This is the user-initiated path. The
    /// security-scoped bookmark refresh and scope re-acquisition happen in the
    /// shared `navigate(to:)` so back/forward navigation gets them too.
    func openExternalURL(_ url: URL) {
        let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        navigate(to: directory ? url : url.deletingLastPathComponent(), restoring: directory ? [] : [url.path])
    }

    func openFolder(_ url: URL) {
        if let current = folderURL, current != url, let frame = currentFrame() {
            backStack.append(frame)
        }
        forwardStack.removeAll()
        navigate(to: url, restoring: [])
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let frame = currentFrame() {
            forwardStack.append(frame)
        }
        navigate(to: previous.url, restoring: previous.selectionPaths)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let frame = currentFrame() {
            backStack.append(frame)
        }
        navigate(to: next.url, restoring: next.selectionPaths)
    }

    /// Snapshot of the current folder + selection for the back/forward
    /// stacks, or nil when no folder is open (nothing worth pushing onto
    /// the history). `selectedURLs` already resolves through the O(1) entry
    /// index added for the bulk-select perf fix, so capturing it here
    /// stays cheap even on large multi-selections.
    private func currentFrame() -> NavigationFrame? {
        guard let folderURL else { return nil }
        return NavigationFrame(
            url: folderURL,
            selectionPaths: selectedURLs.map(\.path)
        )
    }

    /// Bare navigation that does NOT touch back/forward stacks. Used by
    /// `openFolder`, `goBack`, and `goForward` after stack bookkeeping.
    /// Resets selection and triggers a reload.
    ///
    /// `restoring` queues a per-path selection set for the next
    /// successful enumeration so back/forward navigation lands the
    /// user back on the rows they had picked — empty for a fresh
    /// `openFolder()` so user-driven nav still starts clean.
    ///
    /// Refreshes the durable `currentBookmark` so persistence captures the
    /// folder we actually land on — `goBack`/`goForward` route through here
    /// too, so without this a save after navigating Back would persist the
    /// folder the user just left. A bookmark failure here is non-fatal: we
    /// just won't be able to restore this folder across launches in sandboxed
    /// builds, which matches the non-sandboxed behaviour today.
    ///
    /// Balances any outstanding security-scope access on the previous URL,
    /// then re-acquires the claim on the new one — both required for
    /// sandboxed builds. `hasSecurityScopeAccess` and `scopedURL` move as a
    /// single unit so they never diverge; `deinit` balances through
    /// `scopedURL`, mirroring `init(state:)` and the original `openFolder`.
    private func navigate(to url: URL, restoring selectionPaths: [String]) {
        if hasSecurityScopeAccess, let previous = scopedURL {
            previous.stopAccessingSecurityScopedResource()
            hasSecurityScopeAccess = false
            scopedURL = nil
        }
        currentBookmark = try? PersistenceService.makeBookmark(for: url)
        // Re-acquire the claim for the new folder. Resolve through the
        // freshly-made bookmark (not `url` directly) so the URL we claim and
        // store in `scopedURL` carries the same security scope `init(state:)`
        // would resolve on next launch.
        if let bookmark = currentBookmark,
           let scoped = PersistenceService.resolveBookmark(bookmark),
           scoped.startAccessingSecurityScopedResource() {
            hasSecurityScopeAccess = true
            scopedURL = scoped
        }
        folderURL = url
        listScrollID = nil
        treeScrollID = nil
        pendingListScrollPath = nil
        pendingTreeScrollPath = nil
        selection.removeAll()
        projectSearchRoots = nil
        projectSearchWatchers.removeAll()
        searchFilter = .init()
        // Drop the per-folder filters so a query / tag filter applied in the
        // previous folder doesn't bleed into the new listing (matches Finder).
        searchQuery = ""
        tagFilter = nil
        pendingRestoredSelection = selectionPaths
        reload()
        updateDirectoryWatcher()
    }

    /// Spin up (or replace) the FSEvents watcher for the active folder.
    /// Called whenever `folderURL` changes — `init(state:)` post-restore
    /// and every `navigate(to:)`. The watcher's `onChange` hops back to
    /// the main actor and calls `reload()`, so external changes (a `cp`
    /// finishing in Terminal, a download landing) appear without the
    /// user pressing ⌘R.
    private func updateDirectoryWatcher() {
        directoryWatcher?.stop()
        directoryWatcher = nil
        guard watchesDirectories, let url = folderURL else { return }
        directoryWatcher = DirectoryWatcher(url: url) { [weak self] in
            Task { @MainActor [weak self] in
                self?.reload()
            }
        }
    }

    /// Debounced trigger fired by the `searchQuery` setter. Cancels any
    /// in-flight enumeration, then (after a short quiet window) walks the
    /// current folder recursively, collecting entries whose name matches
    /// the query case-insensitively. Empty queries reset the result set
    /// and never schedule a walk.
    private func scheduleSearch(preserveSelection: Bool = false) {
        if !preserveSelection { selection.removeAll() }
        searchTask?.cancel()
        searchCancelToken?.cancel()

        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        let roots = searchRoots
        guard (!trimmed.isEmpty || searchFilter.isActive), !roots.isEmpty else {
            searchEntriesByID.removeAll()
            searchResults = []
            searchReadErrors = 0
            isSearching = false
            // Drop the just-cancelled token's identity so a stale deferred
            // block (which guards on `searchCancelToken === token`) can't
            // match and flip `isSearching` back on after we've cleared it.
            searchCancelToken = nil
            return
        }

        let token = SearchCancelToken()
        searchCancelToken = token
        searchEntriesByID.removeAll()
        searchResults = []
        searchReadErrors = 0
        isSearching = true

        let filter = searchFilter
        let diagnostics = FileSearchDiagnostics()
        let includeHidden = includeHidden
        let initialSortKey = sortKey
        let initialAscending = sortAscending
        let initialFoldersOnTop = foldersOnTop

        searchTask = Task { [weak self] in
            // Always clear the spinner on the way out, even if we get
            // cancelled (folder navigation, supersede, deinit). Without
            // this the sidebar's "Searching…" hint can stick on screen.
            defer {
                Task { @MainActor [weak self] in
                    guard let self, self.searchCancelToken === token else { return }
                    self.isSearching = false
                }
            }

            // Coalesce keystrokes — only the final pause kicks the walk.
            try? await Task.sleep(for: .milliseconds(220))
            if Task.isCancelled || token.isCancelled { return }

            let results = await Task.detached(priority: .userInitiated) { [weak self] in
                var all: [FileEntry] = []
                for root in roots {
                    if token.isCancelled { break }
                    let prefix = all
                    let found = (try? FileSystemService().enumerateMatching(root: root, query: trimmed,
                        includingHidden: includeHidden, isCancelled: { token.isCancelled },
                        onProgress: { [weak self] partial in
                            let sorted = FileEntrySorter.sorted(prefix + partial, by: initialSortKey,
                                ascending: initialAscending, foldersOnTop: initialFoldersOnTop)
                            let index = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                            Task { @MainActor [weak self] in
                                guard let self, self.searchCancelToken === token, !token.isCancelled,
                                      self.isSearching, sorted.count > self.searchResults.count,
                                      self.sortKey == initialSortKey, self.sortAscending == initialAscending,
                                      self.foldersOnTop == initialFoldersOnTop else { return }
                                self.searchEntriesByID = index
                                self.searchResults = sorted
                            }
                        }, filter: filter, diagnostics: diagnostics)) ?? []
                    all.append(contentsOf: found)
                }
                return all
            }.value

            if Task.isCancelled || token.isCancelled { return }
            guard let self else { return }
            while !token.isCancelled {
                let key = self.sortKey
                let ascending = self.sortAscending
                let foldersFirst = self.foldersOnTop
                let (sorted, index) = await Task.detached(priority: .userInitiated) {
                    let sorted = FileEntrySorter.sorted(results, by: key, ascending: ascending, foldersOnTop: foldersFirst)
                    let index = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                    return (sorted, index)
                }.value
                guard !Task.isCancelled, !token.isCancelled else { return }
                if self.sortKey == key, self.sortAscending == ascending, self.foldersOnTop == foldersFirst {
                    self.searchEntriesByID = index
                    self.searchResults = sorted
                    self.searchReadErrors = diagnostics.errorCount
                    break
                }
            }
            let visibleIDs = Set(self.searchResults.map(\.id))
            self.selection.formIntersection(visibleIDs)
        }
    }

    func reload() {
        guard let folderURL else {
            return
        }

        loadTask?.cancel()
        loadCancelToken?.cancel()
        for token in treeLoadTokens.values { token.cancel() }
        treeLoadTokens.removeAll()
        loadingTreePaths.removeAll()
        let loadToken = ProcessRunner.Cancellation()
        loadCancelToken = loadToken
        sizeCancelToken?.cancel()
        // Disk/hidden-file changes invalidate an active recursive query too.
        scheduleSearch(preserveSelection: true)
        isLoading = true
        errorMessage = nil
        // Invalidate computed directory sizes on every reload (navigation and
        // every `.mqdirFileSystemChanged` broadcast funnel through here): a
        // folder's contents may have changed, so a previously-walked total is
        // now suspect. Recomputing is explicit (the user re-invokes "Calculate
        // Size"), so dropping the cache is cheap + correct rather than trying
        // to incrementally patch it. Bumping the generation also tells any
        // in-flight walk from the prior listing not to publish a stale result.
        sizeWalkGeneration &+= 1
        if !computedDirectorySizes.isEmpty { computedDirectorySizes = [:] }
        if !computingSizeIDs.isEmpty { computingSizeIDs = [] }

        let includeHidden = includeHidden

        let loader = directoryLoader
        loadTask = Task { [weak self] in
            do {
                let loadedEntries = try await Task.detached(priority: .userInitiated) {
                    try loader(folderURL, includeHidden, { loadToken.isCancelled })
                }.value

                guard let self, !Task.isCancelled else {
                    return
                }

                entries = FileEntrySorter.sorted(
                    loadedEntries,
                    by: sortKey,
                    ascending: sortAscending,
                    foldersOnTop: foldersOnTop
                )
                if let path = pendingListScrollPath {
                    listScrollID = entries.first(where: { $0.url.path == path })?.id
                    pendingListScrollPath = nil
                }
                // Restore selection from a persisted PaneState if any —
                // intersect saved paths with the freshly enumerated entries
                // so deleted/moved files don't leave dangling IDs.
                if !pendingRestoredSelection.isEmpty {
                    let savedPaths = Set(pendingRestoredSelection)
                    selection = Set(
                        entries.filter { savedPaths.contains($0.url.path) }.map(\.id)
                    )
                    selectionAnchor = selection.first
                    selectionCursor = selection.first
                    if viewMode != .tree { pendingRestoredSelection = [] }
                } else if searchQuery.isEmpty, viewMode != .tree {
                    selection.formIntersection(Set(entries.map(\.id)))
                }
                // A reload can fire mid-rename (e.g. another app touches the
                // folder and the watcher reloads us). `renamingEntryID` is
                // URL-keyed, so it survives the re-enumeration as long as the
                // entry is still on disk — keep rename mode and the live draft
                // intact. If the renamed file vanished, drop out of rename mode
                // cleanly so we don't leave a field bound to a dead row.
                if let renamingID = renamingEntryID,
                   !entries.contains(where: { $0.id == renamingID }) {
                    renamingEntryID = nil
                    renameDraft = ""
                }
                isLoading = false
                // Re-fetch any expanded subtrees so the tree view reflects
                // the same on-disk state the flat list just refreshed against.
                refreshTreeChildren()
            } catch {
                guard let self, !Task.isCancelled else {
                    return
                }

                entries = []
                selection.removeAll()
                // Folder became unreadable mid-rename — there's no row to bind
                // the field to, so drop rename mode cleanly.
                renamingEntryID = nil
                renameDraft = ""
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func setSort(_ key: FileEntrySortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }

        entries = FileEntrySorter.sorted(entries, by: sortKey, ascending: sortAscending, foldersOnTop: foldersOnTop)
        // Apply the same sort across every cached tree subtree so the
        // hierarchy stays internally consistent.
        treeChildren = treeChildren.mapValues {
            FileEntrySorter.sorted($0, by: sortKey, ascending: sortAscending, foldersOnTop: foldersOnTop)
        }
    }

    /// Toggle whether directories pin to the top of every sort. Re-sorts
    /// the live entries immediately so the change is visible without
    /// needing to flip the sort key.
    func setFoldersOnTop(_ value: Bool) {
        guard foldersOnTop != value else { return }
        foldersOnTop = value
        entries = FileEntrySorter.sorted(entries, by: sortKey, ascending: sortAscending, foldersOnTop: foldersOnTop)
        treeChildren = treeChildren.mapValues {
            FileEntrySorter.sorted($0, by: sortKey, ascending: sortAscending, foldersOnTop: foldersOnTop)
        }
    }

    func openSelected() {
        guard let selectedEntry else {
            return
        }

        open(selectedEntry)
    }

    func open(_ entry: FileEntry) {
        if entry.isDirectory {
            openFolder(entry.url)
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    func revealSelected() {
        guard let selectedEntry else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([selectedEntry.url])
    }

    func openParentFolder() {
        guard let folderURL else {
            return
        }

        let parentURL = folderURL.deletingLastPathComponent()
        guard parentURL != folderURL else {
            return
        }

        openFolder(parentURL)
    }

    func toggleHiddenFiles() {
        includeHidden.toggle()
    }

    /// Create "untitled folder" (or "untitled folder 2" / 3 / …) in
    /// the current directory and reload. Mirrors Finder's New Folder
    /// behaviour from the empty-area context menu and the ⌘⇧N shortcut.
    func createNewFolder() {
        guard let folder = folderURL else { return }
        do {
            try FileOperationService.createDirectory(
                at: folder.appendingPathComponent("untitled folder")
            )
            reload()
        } catch {
            FileHandle.standardError.write(
                Data("[mq-dir new folder] \(error.localizedDescription)\n".utf8)
            )
        }
    }

    /// Open every currently-selected URL with the system default app
    /// — including folders, which would otherwise navigate inside the
    /// pane on a plain Enter. This is what ⇧↩ binds to so users can
    /// force "open in Finder/Preview/whatever the OS associates" even
    /// when our pane navigation would have intercepted the click.
    func openSelectedWithDefaultApp() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        for url in urls { NSWorkspace.shared.open(url) }
    }

    /// Duplicate every currently-selected entry. Wraps the existing
    /// `duplicate(_:)` so the Edit-menu ⌘D shortcut and the file
    /// context menu's "Duplicate" item share one path.
    func duplicateSelection(normalizeHangul: Bool = false) {
        let targets = selectedEntries
        guard !targets.isEmpty else { return }
        duplicate(targets, normalizeHangul: normalizeHangul)
    }

    /// Newline-joined POSIX paths of the current selection on the
    /// system pasteboard. Bound to ⌘⌥C — Finder's "Copy as Pathname"
    /// shortcut. Plain text only so a paste in a terminal or text
    /// editor lands the path strings directly.
    func copySelectedFilePathsToPasteboard() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    /// Newline-joined filenames (last path components) of the current
    /// selection on the system pasteboard.
    func copySelectedNamesToPasteboard() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urls.map(\.lastPathComponent).joined(separator: "\n"), forType: .string)
    }

    /// True when cmux.app is installed under any of its known bundle
    /// identifiers — used to gate the "Open in cmux" menu item so it
    /// hides for users who don't have cmux at all.
    var canOpenInCmux: Bool {
        CmuxClient.appURL() != nil
    }

    /// Hand the current folder to cmux as a workspace. Cmux declares
    /// `public.folder` as a CFBundleDocumentType in its Info.plist
    /// and its application(_:open:) wires dropped folders into a new
    /// workspace, so a plain `NSWorkspace.open(_:withApplicationAt:)`
    /// is enough — no URL scheme dance, no AppleScript.
    func openCurrentFolderInCmux() {
        guard let folder = folderURL, let cmux = CmuxClient.appURL() else { return }
        NSWorkspace.shared.open(
            [folder],
            withApplicationAt: cmux,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    /// Open the current folder in Terminal.app. Uses the modern
    /// async-completion variant of `open(_:withApplicationAt:…)` and
    /// fires-and-forgets — Terminal handles the rest.
    func openCurrentFolderInTerminal() {
        guard let folder = folderURL else { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(
            [folder],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    /// Open the current folder *in Finder* — i.e. show its contents in
    /// a Finder window, not reveal it inside its parent. The empty-area
    /// menu's "Open in Finder" entry binds to this.
    func openCurrentFolderInFinder() {
        guard let folder = folderURL else { return }
        NSWorkspace.shared.open(folder)
    }

    /// Write the current folder's POSIX path to the system pasteboard.
    /// Pure plain-text — no `public.file-url` — so a paste in a
    /// terminal or text editor lands the path string directly.
    func copyCurrentFolderPath() {
        guard let folder = folderURL else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(folder.path, forType: .string)
    }

    /// True when the system pasteboard carries one or more file URLs
    /// our `pasteFromPasteboard()` would actually copy. Used by the
    /// empty-area context menu to grey out "Paste" when there's
    /// nothing pasteable.
    var canPasteFiles: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: nil)
    }

    // MARK: Selection (multi-select with cmd / shift)

    /// The range math lives in `mqdirCore.SelectionModel` (pure, value-type,
    /// unit-tested). The VM keeps the three `@Published` properties as the
    /// source of truth views bind to — and other paths (`reload`, `navigate`)
    /// write them directly — so each mutation method snapshots the *current*
    /// published state into a model, runs the pure operation, and writes the
    /// result back. Snapshotting per call (rather than holding a long-lived
    /// mirror) means an external write to `selection`/`selectionAnchor`/
    /// `selectionCursor` is always respected on the next selection gesture.
    private var selectionModel: SelectionModel {
        SelectionModel(selectedIDs: selection, anchor: selectionAnchor, cursor: selectionCursor)
    }

    /// Push a mutated `SelectionModel` back onto the `@Published` properties.
    /// Each assignment is guarded so we only fire `objectWillChange` /
    /// `didSet` for the fields that actually moved — `selection`'s `didSet`
    /// invalidates the selected-size cache, so a redundant write there isn't
    /// free.
    private func applySelection(_ model: SelectionModel) {
        if selection != model.selectedIDs { selection = model.selectedIDs }
        if selectionAnchor != model.anchor { selectionAnchor = model.anchor }
        if selectionCursor != model.cursor { selectionCursor = model.cursor }
    }

    func replaceSelection(_ id: FileEntry.ID) {
        var model = selectionModel
        model.replace(with: id)
        applySelection(model)
    }

    func toggleSelection(_ id: FileEntry.ID) {
        var model = selectionModel
        model.toggle(id)
        applySelection(model)
    }

    func extendSelection(to id: FileEntry.ID) {
        // Tree mode's anchor + target both live inside `treeChildren`,
        // not the flat `entries` array — using `entries` for the
        // range walk made Shift+click silently collapse to a single-
        // row replace whenever either endpoint sat in an expanded
        // subtree. `selectionOrderedRowIDs` picks the right axis for
        // the current view mode.
        var model = selectionModel
        model.extend(to: id, in: selectionOrderedRowIDs)
        applySelection(model)
    }

    /// Row ID sequence Shift-range selection should walk over. Tree mode
    /// uses the flattened DFS of every visible (expanded) row; list mode
    /// uses the standard flat enumeration (or search results when a filter
    /// is active). Reads the cached arrays so a Shift-extend doesn't
    /// re-flatten the tree.
    private var selectionOrderedRowIDs: [FileEntry.ID] {
        (viewMode == .tree ? visibleTreeEntries : cachedVisibleEntries).map(\.id)
    }

    /// Swap one `FileEntry.ID` (a URL) for another across the selection
    /// set, anchor, and cursor. Used by `commitRename`: after a rename the
    /// renamed row's ID changes (ID == URL), so without this the renamed
    /// row would deselect on the next reload. Writes the published props
    /// directly — selection-model snapshotting isn't needed for a plain
    /// member substitution.
    private func migrateSelection(from old: FileEntry.ID, to new: FileEntry.ID) {
        if selection.contains(old) {
            selection.remove(old)
            selection.insert(new)
        }
        if selectionAnchor == old { selectionAnchor = new }
        if selectionCursor == old { selectionCursor = new }
    }

    /// Wipe the selection. Used by the file list when the user clicks
    /// empty pane background — Finder's deselect-on-empty-click pattern.
    func clearSelection() {
        var model = selectionModel
        guard model.clear() else { return }
        applySelection(model)
    }

    /// Select every row currently visible in the list (`visibleEntries`,
    /// which honours the active search filter). Anchors on the first
    /// entry so a follow-up shift-extend has a sensible starting point.
    func selectAll() {
        var model = selectionModel
        model.selectAll(in: visibleEntries.map(\.id))
        applySelection(model)
    }

    /// Write the currently selected file URLs to the system pasteboard
    /// in `public.file-url` form so a follow-up ⌘V in Finder, mqdir
    /// itself, or any other Cocoa file consumer pastes the real files.
    /// No-op on an empty selection.
    func copySelectionToPasteboard() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls.map { $0 as NSURL })
    }

    /// Cut: same as copy but marks the pasteboard so a subsequent
    /// `pasteFromPasteboard()` *moves* the files instead of copying.
    /// macOS doesn't have a standard "cut" pasteboard convention so
    /// we mark with a private type that only mq-dir reads. Other apps
    /// (Finder, terminals) see the file URLs and treat the operation
    /// as a regular copy on their end — there's no way around that
    /// without OS-level cut, and matching Windows cut semantics
    /// inside mq-dir is the user-facing requirement.
    func cutSelectionToPasteboard() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls.map { $0 as NSURL })
        pb.setData(Data(), forType: Self.cutMarkerType)
    }

    /// Pasteboard type that marks a cut operation. Empty data — only
    /// the type's presence matters.
    static let cutMarkerType = CutPasteboard.markerType

    /// Read file URLs off the system pasteboard and copy (or move,
    /// when the pasteboard carries our cut marker) them into the
    /// current folder. Mirrors Finder's ⌘V (copy) and Windows
    /// File Explorer's ⌘V-after-⌘X (move). Silently skips when the
    /// pasteboard has no file URLs or no folder is open.
    func pasteFromPasteboard(normalizeHangul: Bool = false) {
        guard let folder = folderURL else { return }
        let pb = NSPasteboard.general
        guard let sources = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !sources.isEmpty else { return }
        let isCut = pb.types?.contains(Self.cutMarkerType) == true
        var revision = pb.changeCount
        let request = FileWorkRequest(kind: isCut ? .move : .copy, sources: sources,
            destination: folder, normalizeHangul: normalizeHangul)
        FileWorkCenter.shared.submit(request) { outcomes in
            guard isCut, pb.changeCount == revision else { return }
            let remaining = outcomes.filter { $0.status != .succeeded }.flatMap(\.sources)
            CutPasteboard.complete(pb, changeCount: revision, remainingURLs: remaining)
            revision = pb.changeCount
        }
    }

    /// Convenience around `moveToTrash` that operates on the live
    /// selection. Used by the Edit menu's Delete shortcut so the user
    /// doesn't need to right-click to trash files.
    func moveSelectionToTrash() {
        let targets = selectedEntries
        guard !targets.isEmpty else { return }
        moveToTrash(targets)
    }

    /// Permanent delete with a destructive NSAlert confirmation.
    /// Bypasses the trash via `FileManager.removeItem(at:)`. Used by
    /// Edit → Delete Immediately (⌘⌥⌫) and the file context menu.
    /// Failures are surfaced in a follow-up alert listing the items
    /// that could not be removed so the operation is never silently
    /// partial.
    func permanentlyDelete(_ entries: [FileEntry]) {
        guard !entries.isEmpty else { return }
        let urls = entries.map(\.url)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = urls.count == 1
            ? "Delete \u{201C}\(urls[0].lastPathComponent)\u{201D} permanently?"
            : "Delete \(urls.count) items permanently?"
        alert.informativeText = "These items will be deleted immediately. You can't undo this action."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        FileWorkCenter.shared.submit(FileWorkRequest(kind: .delete, sources: urls))
    }

    /// Selection wrapper for `permanentlyDelete(_:)` so the Edit menu
    /// shortcut and the context menu share one path.
    func permanentlyDeleteSelection() {
        let targets = selectedEntries
        guard !targets.isEmpty else { return }
        permanentlyDelete(targets)
    }

    /// Compress every entry in `entries` into a single .zip in their
    /// shared parent folder via /usr/bin/zip. Mirrors Finder's
    /// "Compress N items": single selection becomes "<name>.zip"
    /// (folder keeps its name; file drops its extension); multi-
    /// selection becomes "Archive.zip". Collisions auto-rename to
    /// "<name> 2.zip" / "Archive 2.zip" / … (Finder convention).
    /// Cross-folder selections are rejected because zip's relative
    /// pathing assumes a single working directory.
    func compress(_ entries: [FileEntry]) {
        FileWorkCenter.shared.submit(FileWorkRequest(kind: .compress, sources: entries.map(\.url)))
    }

    /// True when every entry in `entries` is an archive we know how
    /// to extract (case-insensitive .zip / .tar / .tgz / .tar.gz).
    /// Used by the context menu to decide whether the "Extract"
    /// item is enabled. An empty list returns false so the entry is
    /// hidden when no rows are selected. Thin wrapper over
    /// `FileOperationService.canExtract`.
    nonisolated static func canExtract(_ entries: [FileEntry]) -> Bool {
        FileOperationService.canExtract(
            entries.map { (url: $0.url, isDirectory: $0.isDirectory) }
        )
    }

    /// Extract every supported archive in `entries` into a sibling
    /// folder named after the archive stem. Each archive runs through
    /// /usr/bin/ditto (zip) or /usr/bin/tar (tar/tgz/tar.gz) on a
    /// detached utility task. After the batch finishes the VM hops
    /// back to the main actor, broadcasts a filesystem change so any
    /// open pane on the same folder picks up the new directory, and
    /// surfaces a single NSAlert with the archives that failed.
    func extractArchives(_ entries: [FileEntry]) {
        let sources = entries.filter { !$0.isDirectory && FileOperationService.archiveKind(for: $0.url) != nil }.map(\.url)
        FileWorkCenter.shared.submit(FileWorkRequest(kind: .extract, sources: sources))
    }

    /// True when `entries` contains at least one directory — gates the
    /// "Calculate Size" context-menu item (folders are the only entries that
    /// lack a size). A pure predicate over the passed targets so the menu can
    /// hide the action for an all-files selection.
    nonisolated static func canCalculateSize(_ entries: [FileEntry]) -> Bool {
        entries.contains { $0.isDirectory }
    }

    /// On-demand size calculation for every directory in `entries`. Files are
    /// ignored (they already carry a size). Each folder is walked recursively
    /// off the main actor at utility priority; the running set drives the "…"
    /// progress text and the result publishes into `computedDirectorySizes`,
    /// which repaints the size column and feeds the status-bar selected total.
    ///
    /// A generation token captured at launch lets a walk that outlived its
    /// folder (navigation / reload bumps the generation) skip publishing —
    /// the stale-write-is-harmless property holds because IDs are URLs, but
    /// dropping it keeps the cache from accreting dead entries.
    func calculateSize(_ entries: [FileEntry]) {
        let directories = entries.filter(\.isDirectory)
        guard !directories.isEmpty else { return }
        sizeCancelToken?.cancel()
        let token = ProcessRunner.Cancellation()
        sizeCancelToken = token
        sizeWalkGeneration &+= 1
        let generation = sizeWalkGeneration
        computingSizeIDs = Set(directories.map(\.id))
        Task { [weak self] in
            // One size walk at a time per request instead of one detached
            // task per selected folder. Superseded requests stop cooperatively.
            for directory in directories {
                if token.isCancelled { break }
                let url = directory.url
                let size = await Task.detached(priority: .utility) {
                    FileSystemService().directorySize(at: url, isCancelled: { token.isCancelled })
                }.value
                guard let self, !token.isCancelled, self.sizeWalkGeneration == generation else { return }
                self.computedDirectorySizes[directory.id] = size
                self.computingSizeIDs.remove(directory.id)
            }
        }
    }

    /// Move the selection up or down by `offset` rows in `visibleEntries`,
    /// the same set the file list renders. With `extending: true` (Shift
    /// held) grows the selection from the anchor instead of replacing it,
    /// matching Finder's arrow-key behavior. No-op on an empty list.
    func moveSelection(by offset: Int, extending: Bool) {
        // In tree mode walk the flat DFS of expanded rows (matches what
        // the user sees). In list mode keep the existing flat-listing
        // walk so search-result navigation also works. Both read the cached
        // arrays so a held arrow key doesn't re-flatten/re-allocate per repeat.
        // The pivot/clamp/extend math (including the documented Shift-growth
        // fix — stepping from the cursor, not the anchor) lives in
        // `SelectionModel.move`.
        let visible = (viewMode == .tree ? visibleTreeEntries : cachedVisibleEntries).map(\.id)
        var model = selectionModel
        model.move(by: offset, extending: extending, in: visible)
        applySelection(model)
    }

    /// Every currently-selected entry, resolved across the flat root
    /// listing AND every cached tree subtree. Tree-mode selections
    /// live in `treeChildren`, never in `entries`, so list-only walks
    /// silently miss them — hence the `findEntry`-driven path.
    var selectedEntries: [FileEntry] {
        selection.compactMap { findEntry(id: $0) }
    }

    /// URLs of every currently-selected entry. Order is set-iteration
    /// order — fine for cut/copy/move where the destination handles
    /// each independently.
    var selectedURLs: [URL] {
        selectedEntries.map(\.url)
    }

    /// Total byte size of the current selection, summed across the O(1)
    /// entry index. Memoized so the global status bar's per-render read
    /// doesn't re-run the `compactMap`/`reduce` on every `MainWindowView`
    /// body invalidation; recomputes only when selection or entry data moves.
    var selectedSize: Int64 {
        if let cached = cachedSelectedSize { return cached }
        let total = selection.reduce(Int64(0)) { running, id in
            // A selected directory contributes its computed size when one has
            // been calculated (folders carry `size == nil` otherwise); files
            // contribute their own `size`. `computedDirectorySizes` keys on
            // the same URL-ID so the lookup is O(1).
            running + (findEntry(id: id)?.size ?? computedDirectorySizes[id] ?? 0)
        }
        cachedSelectedSize = total
        return total
    }

    /// Deduplicated tag summaries for the current folder's entries, feeding
    /// the sidebar's Tags section. Memoized so the sidebar's per-render read
    /// doesn't re-walk every entry's tags on each `MainWindowView` body pass;
    /// recomputes only when `entries` changes.
    var tagSummaries: [TagSummary] {
        if let cached = cachedTagSummaries { return cached }
        let summaries = entries.uniqueTagSummaries()
        cachedTagSummaries = summaries
        return summaries
    }

    /// Right-click "Duplicate" → for each entry, copy in place with a
    /// Finder-style " 2" / " 3" suffix. Mirrors `acceptDrop`'s detached-task
    /// + system-wide reload pattern so an open second pane viewing the same
    /// folder also picks up the new copies.
    func duplicate(_ entries: [FileEntry], normalizeHangul: Bool = false) {
        FileWorkCenter.shared.submit(FileWorkRequest(kind: .duplicate, sources: entries.map(\.url), normalizeHangul: normalizeHangul))
    }

    /// Begin inline rename for `entry`. Seeds the draft with the
    /// current name and selects the row so the rename field the row
    /// renders is pointed at the right item. If a *different* row is
    /// already mid-rename, commit it first — only one row is ever in
    /// rename mode, and starting a fresh rename shouldn't silently
    /// discard the in-flight edit (Finder commits the old one).
    func beginRename(_ entry: FileEntry) {
        if let active = renamingEntryID, active != entry.id {
            commitRename()
        }
        renamingEntryID = entry.id
        renameDraft = entry.name
        replaceSelection(entry.id)
    }

    /// Begin inline rename for the currently-active selection. Used by
    /// the ⌘⇧R menu shortcut. No-op if nothing is selected.
    func beginRenameForActiveSelection() {
        guard let entry = selectedEntry else { return }
        beginRename(entry)
    }

    /// Tab / Shift-Tab while renaming: commit the current edit, then begin
    /// renaming the next (`forward`) or previous visible row, Finder-style.
    /// Walks the same row order arrow-key nav uses (tree DFS in tree mode,
    /// the flat visible list otherwise). No-op past the first / last row.
    func beginRenameAdjacent(forward: Bool) {
        guard let currentID = renamingEntryID else { return }
        // commitRename clears renamingEntryID; capture the order first.
        let rows = selectionOrderedRowIDs
        commitRename()
        guard let idx = rows.firstIndex(of: currentID) else { return }
        let nextIdx = forward ? idx + 1 : idx - 1
        guard rows.indices.contains(nextIdx),
              let entry = findEntry(id: rows[nextIdx])
        else { return }
        beginRename(entry)
    }

    /// Commit the in-progress rename. Trims whitespace, no-ops on
    /// empty / unchanged names, refuses to overwrite an existing
    /// sibling, then `FileManager.moveItem` and reloads. Always
    /// clears the rename mode at the end so the row drops back to
    /// static text.
    func commitRename() {
        defer {
            renamingEntryID = nil
            renameDraft = ""
        }
        guard let id = renamingEntryID,
              let entry = findEntry(id: id)
        else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.name else { return }

        FileWorkCenter.shared.submit(FileWorkRequest(kind: .rename, sources: [entry.url], newName: trimmed)) { [weak self] outcomes in
            guard let self, let outcome = outcomes.first, outcome.status == .succeeded, let newURL = outcome.destination else { return }
            self.migrateSelection(from: entry.id, to: newURL)
        }

    }

    /// Discard the in-progress rename without touching the filesystem.
    func cancelRename() {
        renamingEntryID = nil
        renameDraft = ""
    }

    /// Rename any decomposed-Hangul (NFD) filenames in `entries` to
    /// NFC form on disk. This is the explicit right-click "Normalize
    /// Filename to NFC" action. The same `HangulNFCFilename.renameToNFC`
    /// primitive is also driven automatically — gated by the
    /// `normalizeHangulOnDragOut` workspace setting — by the drag-out
    /// source modifiers (`appKitFileDrag` / `inactiveDragSource`) at
    /// drag-start and by `FileOperationService.transfer` / `duplicate`
    /// after a copy/move/duplicate. `renameToNFC` bypasses
    /// `FileManager.moveItem` (a no-op on APFS for normalisation-only
    /// renames). Reloads at the end if anything actually changed.
    func normalizeFilenamesToNFC(_ entries: [FileEntry]) {
        var changed = false
        for entry in entries {
            if HangulNFCFilename.renameToNFC(entry.url) != nil {
                changed = true
            }
        }
        if changed { reload() }
    }

    /// Right-click "Move to Trash" → `FileManager.trashItem` per entry.
    /// Failures (permission, missing file) are logged to stderr and skipped
    /// so a partial selection doesn't abort the whole operation.
    /// Toggle the standard Finder colour `label` (1-7) across each
    /// entry, or clear every tag when `label == 0`. Matches Finder's
    /// status-bar colour-dot bar behaviour where re-picking a colour
    /// unsets it. After the writes complete, broadcasts a refresh so
    /// every open pane re-enumerates and the dot palette repaints
    /// against the freshly-written `_kMDItemUserTags`.
    func toggleColorTag(_ label: Int, on entries: [FileEntry]) {
        let urls = entries.map(\.url)
        let displayName = TagColor.displayName(forLabel: label)
        Task {
            await Task.detached(priority: .userInitiated) {
                for url in urls {
                    do {
                        try FileSystemService.toggleColourTag(
                            label: label,
                            displayName: displayName,
                            on: url
                        )
                    } catch {
                        FileHandle.standardError.write(
                            Data("[mq-dir tag] \(url.lastPathComponent): \(error.localizedDescription)\n".utf8)
                        )
                    }
                }
            }.value
            FileSystemChange.post(folders: urls.map { $0.deletingLastPathComponent() })
        }
    }



    func moveToTrash(_ entries: [FileEntry]) {
        FileWorkCenter.shared.submit(FileWorkRequest(kind: .trash, sources: entries.map(\.url)))
    }

    /// Move (or copy across volumes) a list of file URLs into a destination folder.
    /// `copy=true` forces copy (Option held). Default Finder semantics: same-volume = move,
    /// cross-volume = copy. On name conflict, the destination gets " 2", " 3", ... suffix
    /// (Finder convention). After completion, broadcasts a system-wide reload.
    func acceptDrop(_ urls: [URL], into destinationFolder: URL, copy: Bool, normalizeHangul: Bool = false) {
        FileWorkCenter.shared.submit(FileWorkRequest(kind: .drop, sources: urls,
            destination: destinationFolder, forceCopy: copy, normalizeHangul: normalizeHangul))
    }
}

/// Thread-safe one-shot cancel flag handed across actor boundaries to the
/// detached enumerator. Detached tasks don't inherit Swift's structured
/// cancellation, so we propagate intent through this Sendable token instead.
final class SearchCancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        _cancelled = true
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }
}
