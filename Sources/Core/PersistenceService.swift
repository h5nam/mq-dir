import Foundation

/// Per-pane state that survives an app restart.
///
/// Folder reference is stored as a security-scoped bookmark (not a raw path)
/// so the file manager remains operable when the app moves to the App Store
/// sandbox. Selection is stored as URL-paths and re-intersected with the
/// freshly enumerated entries on restore.
struct PaneState: Codable, Equatable, Sendable {
    var folderBookmark: Data?
    var sortKey: FileEntrySortKey
    var sortAscending: Bool
    var includeHidden: Bool
    var columnWidths: PaneColumnWidths
    var selectedURLPaths: [String]

    init(
        folderBookmark: Data? = nil,
        sortKey: FileEntrySortKey = .name,
        sortAscending: Bool = true,
        includeHidden: Bool = false,
        columnWidths: PaneColumnWidths = PaneColumnWidths(),
        selectedURLPaths: [String] = []
    ) {
        self.folderBookmark = folderBookmark
        self.sortKey = sortKey
        self.sortAscending = sortAscending
        self.includeHidden = includeHidden
        self.columnWidths = columnWidths
        self.selectedURLPaths = selectedURLPaths
    }
}

/// Window-level state that survives an app restart.
///
/// Always carries four pane states even when `layout` shows fewer panes,
/// so that growing the layout (e.g. single → 4-pane) restores the
/// previously-loaded folders rather than reverting to empty.
struct WindowState: Codable, Equatable, Sendable {
    var layout: PaneLayout
    var focusedPaneIndex: Int
    var panes: [PaneState]

    init(layout: PaneLayout, focusedPaneIndex: Int, panes: [PaneState]) {
        precondition(panes.count == 4, "WindowState always carries exactly 4 pane records")
        self.layout = layout
        self.focusedPaneIndex = focusedPaneIndex
        self.panes = panes
    }

    static let empty = WindowState(
        layout: .four,
        focusedPaneIndex: 0,
        panes: Array(repeating: PaneState(), count: 4)
    )
}

/// Reads and writes the persisted window state to disk.
///
/// I/O is intentionally synchronous on the call site; the *caller* (typically
/// `MainWindowView` for debounced saves) is responsible for hopping off the
/// main thread via `Task.detached`. This keeps the service itself a thin,
/// testable wrapper around `JSONEncoder` / `Data.write(to:)` rather than a
/// concurrency boundary.
// `@unchecked Sendable` because the only stored property that isn't
// trivially `Sendable` is `FileManager`, which Apple documents as
// thread-safe for the read/write/exist/createDirectory operations we use.
// We never mutate the manager itself — its delegate is left nil.
struct PersistenceService: @unchecked Sendable {
    private let stateURL: URL
    private let fileManager: FileManager

    /// Production initializer: writes to
    /// `~/Library/Application Support/com.mqdir.app/state.json`.
    /// Throws if the support directory cannot be located or created.
    init(fileManager: FileManager = .default) throws {
        let supportRoot = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleDir = supportRoot.appendingPathComponent("com.mqdir.app", isDirectory: true)
        if !fileManager.fileExists(atPath: bundleDir.path) {
            try fileManager.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        }
        self.stateURL = bundleDir.appendingPathComponent("state.json", isDirectory: false)
        self.fileManager = fileManager
    }

    /// Test initializer: writes to an explicit URL. Creates the parent
    /// directory if needed. Used so tests don't touch the real
    /// `~/Library/Application Support`.
    init(stateURL: URL, fileManager: FileManager = .default) throws {
        let parent = stateURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        self.stateURL = stateURL
        self.fileManager = fileManager
    }

    /// Returns nil when the file is missing, unreadable, or contains
    /// corrupt JSON. Callers always treat a `nil` load as "first launch".
    /// Never throws — corruption recovery is part of the contract.
    func loadState() -> WindowState? {
        guard fileManager.fileExists(atPath: stateURL.path) else { return nil }
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(WindowState.self, from: data)
    }

    /// Writes the state atomically. Throws so the caller (typically a
    /// debounced save) can log a failure without crashing.
    func saveState(_ state: WindowState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: [.atomic])
    }

    /// On-disk location of the state file (exposed for diagnostics/tests).
    var fileURL: URL { stateURL }

    // MARK: - Bookmarks

    /// Creates a security-scoped bookmark for an existing folder URL.
    /// The caller stores the returned `Data` in `PaneState.folderBookmark`.
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves a previously-saved bookmark back to its URL.
    /// Returns `nil` if the bookmark is corrupt. The *caller* is responsible
    /// for calling `startAccessingSecurityScopedResource()` on the returned
    /// URL. A *stale* bookmark still resolves; we surface the URL so the
    /// caller can refresh on next openFolder rather than losing the entry.
    static func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
