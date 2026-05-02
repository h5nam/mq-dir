import AppKit
import CoreGraphics
import Foundation

// `PaneColumnWidths` and `FileEntrySortKey` now live in `Sources/Core/` so
// that persisted pane state is fully testable from `swift test`. They are
// re-exported by being members of the same Xcode module.

@MainActor
final class FolderBrowserViewModel: ObservableObject {
    @Published private(set) var folderURL: URL?
    @Published private(set) var entries: [FileEntry] = []
    @Published var selection: Set<FileEntry.ID> = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var includeHidden = false {
        didSet {
            reload()
        }
    }
    @Published private(set) var sortKey: FileEntrySortKey = .name
    @Published private(set) var sortAscending = true
    @Published var columnWidths = PaneColumnWidths()
    @Published private(set) var backStack: [URL] = []
    @Published private(set) var forwardStack: [URL] = []
    @Published private(set) var selectionAnchor: FileEntry.ID?

    /// Restored selection paths waiting to be matched against the next
    /// successful `entries` enumeration. Cleared after the match runs.
    private var pendingRestoredSelection: [String] = []

    /// Bookmark for the currently-open `folderURL`, refreshed on each
    /// `openFolder` so a `paneSnapshot()` returns durable state without
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

    private var loadTask: Task<Void, Never>?

    /// Default initializer — fresh, empty pane (used by previews and the
    /// first launch when no persisted state exists).
    init() {}

    /// Restoration initializer — rehydrates a pane from a saved `PaneState`.
    /// If the bookmark resolves, opens the folder and queues the saved
    /// selection to be matched against the loaded entries.
    init(state: PaneState) {
        self.sortKey = state.sortKey
        self.sortAscending = state.sortAscending
        self.includeHidden = state.includeHidden
        self.columnWidths = state.columnWidths
        self.pendingRestoredSelection = state.selectedURLPaths

        if let bookmark = state.folderBookmark,
           let resolved = PersistenceService.resolveBookmark(bookmark) {
            self.currentBookmark = bookmark
            // Sandbox-readiness: claim security scope before any I/O.
            if resolved.startAccessingSecurityScopedResource() {
                self.hasSecurityScopeAccess = true
                self.scopedURL = resolved
            }
            self.folderURL = resolved
            reload()
        }
    }

    deinit {
        // Balance any outstanding security-scope claim. `scopedURL` is the
        // nonisolated mirror — deinit can't touch main-actor state, so we
        // only release through this side-channel pointer.
        if let url = scopedURL {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Snapshot the live pane state for serialization.
    func paneSnapshot() -> PaneState {
        PaneState(
            folderBookmark: currentBookmark,
            sortKey: sortKey,
            sortAscending: sortAscending,
            includeHidden: includeHidden,
            columnWidths: columnWidths,
            selectedURLPaths: selectedURLs.map(\.path)
        )
    }

    var selectedEntry: FileEntry? {
        guard let selectedID = selection.first else {
            return nil
        }

        return entries.first { $0.id == selectedID }
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
    /// and clearing the forward stack. This is the user-initiated path.
    /// Refreshes the security-scoped bookmark so persistence captures the
    /// latest folder reference without a separate "save bookmark" step.
    func openFolder(_ url: URL) {
        if let current = folderURL, current != url {
            backStack.append(current)
        }
        forwardStack.removeAll()
        // Refresh the durable bookmark for persistence. A failure here is
        // non-fatal — we just won't be able to restore this folder across
        // launches in sandboxed builds, which matches non-sandboxed today.
        currentBookmark = try? PersistenceService.makeBookmark(for: url)
        navigate(to: url)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let current = folderURL {
            forwardStack.append(current)
        }
        navigate(to: previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = folderURL {
            backStack.append(current)
        }
        navigate(to: next)
    }

    /// Bare navigation that does NOT touch back/forward stacks. Used by
    /// `goBack`, `goForward`, and the initial `openFolder` after stack
    /// bookkeeping. Resets selection and triggers a reload.
    ///
    /// Balances any outstanding security-scope access on the previous URL
    /// before assigning the new one — required for sandboxed builds.
    private func navigate(to url: URL) {
        if hasSecurityScopeAccess, let previous = folderURL, previous != url {
            previous.stopAccessingSecurityScopedResource()
            hasSecurityScopeAccess = false
            scopedURL = nil
        }
        folderURL = url
        selection.removeAll()
        // User-driven navigation supersedes any pending restored selection.
        pendingRestoredSelection = []
        reload()
    }

    func reload() {
        guard let folderURL else {
            return
        }

        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        let includeHidden = includeHidden
        let sortKey = sortKey
        let sortAscending = sortAscending

        loadTask = Task {
            do {
                let loadedEntries = try await Task.detached(priority: .userInitiated) {
                    try FileSystemService().enumerateDirectory(
                        at: folderURL,
                        includingHidden: includeHidden
                    )
                }.value

                guard !Task.isCancelled else {
                    return
                }

                entries = FileEntrySorter.sorted(
                    loadedEntries,
                    by: sortKey,
                    ascending: sortAscending
                )
                // Restore selection from a persisted PaneState if any —
                // intersect saved paths with the freshly enumerated entries
                // so deleted/moved files don't leave dangling IDs.
                if !pendingRestoredSelection.isEmpty {
                    let savedPaths = Set(pendingRestoredSelection)
                    selection = Set(
                        entries.filter { savedPaths.contains($0.url.path) }.map(\.id)
                    )
                    selectionAnchor = selection.first
                    pendingRestoredSelection = []
                } else {
                    selection = selection.filter { selectedID in
                        entries.contains { $0.id == selectedID }
                    }
                }
                isLoading = false
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                entries = []
                selection.removeAll()
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

        entries = FileEntrySorter.sorted(entries, by: sortKey, ascending: sortAscending)
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

    // MARK: Selection (multi-select with cmd / shift)

    func replaceSelection(_ id: FileEntry.ID) {
        selection = [id]
        selectionAnchor = id
    }

    func toggleSelection(_ id: FileEntry.ID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        selectionAnchor = id
    }

    func extendSelection(to id: FileEntry.ID) {
        guard let anchor = selectionAnchor,
              let anchorIdx = entries.firstIndex(where: { $0.id == anchor }),
              let targetIdx = entries.firstIndex(where: { $0.id == id })
        else {
            replaceSelection(id)
            return
        }
        let lower = min(anchorIdx, targetIdx)
        let upper = max(anchorIdx, targetIdx)
        selection = Set(entries[lower...upper].map(\.id))
    }

    /// URLs of every currently-selected entry, in row order.
    var selectedURLs: [URL] {
        entries.filter { selection.contains($0.id) }.map(\.url)
    }

    /// Move (or copy across volumes) a list of file URLs into a destination folder.
    /// `copy=true` forces copy (Option held). Default Finder semantics: same-volume = move,
    /// cross-volume = copy. On name conflict, the destination gets " 2", " 3", ... suffix
    /// (Finder convention). After completion, broadcasts a system-wide reload.
    func acceptDrop(_ urls: [URL], into destinationFolder: URL, copy: Bool) {
        Task {
            await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                for source in urls {
                    var dest = destinationFolder.appendingPathComponent(source.lastPathComponent)
                    if source == dest { continue }
                    // Reject dropping a folder into itself or any descendant.
                    if dest.path.hasPrefix(source.path + "/") { continue }
                    // Auto-rename on conflict instead of skipping.
                    if fm.fileExists(atPath: dest.path) {
                        dest = Self.uniqueDestination(for: source, in: destinationFolder)
                    }
                    do {
                        if copy {
                            try fm.copyItem(at: source, to: dest)
                        } else {
                            try fm.moveItem(at: source, to: dest)
                        }
                    } catch {
                        FileHandle.standardError.write(
                            Data("[mq-dir drop] \(source.lastPathComponent): \(error.localizedDescription)\n".utf8)
                        )
                    }
                }
            }.value
            NotificationCenter.default.post(name: .mqdirFileSystemChanged, object: nil)
        }
    }

    /// Generates "name 2.ext", "name 3.ext", ... for the first non-existent path.
    /// Caps at 500 attempts; falls back to a timestamped name to avoid hanging.
    nonisolated static func uniqueDestination(for source: URL, in folder: URL) -> URL {
        let fm = FileManager.default
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        for n in 2...500 {
            let suffix = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            let candidate = folder.appendingPathComponent(suffix)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let fallback = ext.isEmpty ? "\(stem)-\(stamp)" : "\(stem)-\(stamp).\(ext)"
        return folder.appendingPathComponent(fallback)
    }
}

