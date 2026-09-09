import Foundation

/// Per-load recovery evidence; never shared between decoder invocations.
private final class StateDecodingRecovery: @unchecked Sendable {
    static let key = CodingUserInfoKey(rawValue: "mqdir.stateRecovery")!
    // JSONDecoder.userInfo requires Sendable values. Protect the only mutable
    // field even though each decoder currently performs its work serially.
    private let lock = NSLock()
    private var didRepair = false
    var repaired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didRepair
    }

    private func markRepaired() {
        lock.lock()
        defer { lock.unlock() }
        didRepair = true
    }

    static func record(in decoder: Decoder) {
        (decoder.userInfo[key] as? StateDecodingRecovery)?.markRepaired()
    }
}

extension KeyedDecodingContainer {
    /// Decode `key` if present and well-formed, otherwise fall back to
    /// `defaultValue`. Collapses the repeated
    /// `(try? decodeIfPresent(...)) ?? default` boilerplate used by every
    /// hand-rolled migration decoder in this file so a missing *or* malformed
    /// field degrades to the default instead of failing the whole decode.
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(type, forKey: key)) ?? defaultValue
    }

    /// Decode `[Element]` element-by-element through an unkeyed container,
    /// skipping any element that fails to decode while keeping the good ones.
    /// Returns `nil` only when the key is absent or isn't an array at all — a
    /// present-but-partly-corrupt array yields the surviving elements. This
    /// mirrors the per-entry resilience of `WorkspaceSettings`'
    /// `shortcutOverrides` decode: one bad record must not nuke the array.
    func decodeArraySkippingInvalid<Element: Decodable>(
        _ elementType: Element.Type,
        forKey key: Key
    ) -> [Element]? {
        guard var unkeyed = try? nestedUnkeyedContainer(forKey: key) else { return nil }
        var result: [Element] = []
        while !unkeyed.isAtEnd {
            if let element = try? unkeyed.decode(Element.self) {
                result.append(element)
            } else {
                // The element threw — advance the cursor past it so the loop
                // terminates instead of spinning on the same bad record.
                _ = try? unkeyed.decode(AnyDecodableSkip.self)
            }
        }
        return result
    }

    /// Preserve positions when recovering pane/tab arrays so a damaged record
    /// cannot shift another folder into the user's active pane or tab.
    func decodeArrayReplacingInvalid<Element: Decodable>(
        _ type: Element.Type,
        forKey key: Key,
        default defaultValue: Element
    ) -> [Element]? {
        guard contains(key), let arrayDecoder = try? superDecoder(forKey: key) else { return nil }
        guard var items = try? arrayDecoder.unkeyedContainer() else {
            StateDecodingRecovery.record(in: arrayDecoder)
            return nil
        }
        var result: [Element] = []
        while !items.isAtEnd {
            // superDecoder advances exactly one slot even if decoding fails.
            guard let decoder = try? items.superDecoder() else { return result }
            do {
                result.append(try Element(from: decoder))
            } catch {
                StateDecodingRecovery.record(in: decoder)
                result.append(defaultValue)
            }
        }
        return result
    }
}

/// Throwaway decodable used to consume and discard one element of an
/// unkeyed container whose real type failed to decode, advancing the
/// decoder's cursor so element-skipping array decode can proceed.
private struct AnyDecodableSkip: Decodable {
    init(from decoder: Decoder) throws {
        _ = try decoder.singleValueContainer()
    }
}

/// Per-tab state that survives an app restart.
///
/// Folder reference is stored as a security-scoped bookmark (not a raw path)
/// so the file manager remains operable when the app moves to the App Store
/// sandbox. Selection is stored as URL-paths and re-intersected with the
/// freshly enumerated entries on restore.
struct TabState: Codable, Equatable, Sendable {
    var folderBookmark: Data?
    var sortKey: FileEntrySortKey
    var sortAscending: Bool
    var includeHidden: Bool
    var columnWidths: PaneColumnWidths
    var selectedURLPaths: [String]
    /// `.list` flat columns vs `.tree` VS Code-style nested view.
    var viewMode: PaneViewMode
    /// Filesystem paths the tree view should render expanded. Stored as
    /// raw paths (not bookmarks) because they're positional cues — losing
    /// access to a folder just means it renders collapsed, not broken.
    var expandedPaths: [String]
    /// Whether the right-side preview panel is visible for this tab.
    /// Defaults off so existing tabs don't grow a new chrome surface
    /// behind the user's back on upgrade.
    var previewVisible: Bool
    var listScrollPath: String?
    var treeScrollPath: String?
    /// When true, directories sort ahead of files within the same key.
    /// Defaults true to preserve the historical Finder-list behaviour
    /// for upgraded state.json files; user can flip it per tab from the
    /// column header context menu when they want pure key-only sorting.
    var foldersOnTop: Bool

    init(
        folderBookmark: Data? = nil,
        sortKey: FileEntrySortKey = .name,
        sortAscending: Bool = true,
        includeHidden: Bool = false,
        columnWidths: PaneColumnWidths = PaneColumnWidths(),
        selectedURLPaths: [String] = [],
        viewMode: PaneViewMode = .list,
        expandedPaths: [String] = [],
        previewVisible: Bool = false,
        foldersOnTop: Bool = true,
        listScrollPath: String? = nil,
        treeScrollPath: String? = nil
    ) {
        self.folderBookmark = folderBookmark
        self.sortKey = sortKey
        self.sortAscending = sortAscending
        self.includeHidden = includeHidden
        self.columnWidths = columnWidths
        self.selectedURLPaths = selectedURLPaths
        self.viewMode = viewMode
        self.expandedPaths = expandedPaths
        self.previewVisible = previewVisible
        self.foldersOnTop = foldersOnTop
        self.listScrollPath = listScrollPath
        self.treeScrollPath = treeScrollPath
    }

    /// Default the new fields when reading a `state.json` written before
    /// the tree view / preview pane existed. Without this the auto-synthesized
    /// decoder would refuse to load any old file.
    private enum CodingKeys: String, CodingKey {
        case folderBookmark, sortKey, sortAscending, includeHidden,
             columnWidths, selectedURLPaths, viewMode, expandedPaths,
             previewVisible, foldersOnTop, listScrollPath, treeScrollPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            folderBookmark: c.decode(Data?.self, forKey: .folderBookmark, default: nil),
            sortKey: c.decode(FileEntrySortKey.self, forKey: .sortKey, default: .name),
            sortAscending: c.decode(Bool.self, forKey: .sortAscending, default: true),
            includeHidden: c.decode(Bool.self, forKey: .includeHidden, default: false),
            columnWidths: c.decode(PaneColumnWidths.self, forKey: .columnWidths, default: PaneColumnWidths()),
            selectedURLPaths: c.decode([String].self, forKey: .selectedURLPaths, default: []),
            viewMode: c.decode(PaneViewMode.self, forKey: .viewMode, default: .list),
            expandedPaths: c.decode([String].self, forKey: .expandedPaths, default: []),
            previewVisible: c.decode(Bool.self, forKey: .previewVisible, default: false),
            foldersOnTop: c.decode(Bool.self, forKey: .foldersOnTop, default: true),
            listScrollPath: c.decode(String?.self, forKey: .listScrollPath, default: nil),
            treeScrollPath: c.decode(String?.self, forKey: .treeScrollPath, default: nil)
        )
    }
}

/// Per-pane state. A pane carries an ordered list of tabs and which one is
/// currently active. Always carries at least one tab so the pane is never
/// in a tabless state — closing the last tab leaves an empty tab in place.
struct PaneState: Codable, Equatable, Sendable {
    var tabs: [TabState]
    var activeTabIndex: Int

    init(tabs: [TabState] = [TabState()], activeTabIndex: Int = 0) {
        precondition(!tabs.isEmpty, "PaneState must carry at least one tab")
        self.tabs = tabs
        self.activeTabIndex = max(0, min(activeTabIndex, tabs.count - 1))
    }

    /// Backward-compat decode: pre-tabs `state.json` had each pane stored as
    /// a flat `TabState` (folderBookmark/sortKey/...). Detect that shape and
    /// promote it to a single-tab pane so users don't lose their last folder.
    private enum CodingKeys: String, CodingKey {
        case tabs, activeTabIndex
    }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           c.contains(.tabs)
        {
            let tabs = c.decodeArrayReplacingInvalid(TabState.self, forKey: .tabs, default: TabState()) ?? []
            let active = (try? c.decodeIfPresent(Int.self, forKey: .activeTabIndex)) ?? 0
            self.init(
                tabs: tabs.isEmpty ? [TabState()] : tabs,
                activeTabIndex: active
            )
            return
        }
        // Legacy shape: decode the whole container as a single TabState.
        let legacy = try TabState(from: decoder)
        self.init(tabs: [legacy], activeTabIndex: 0)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tabs, forKey: .tabs)
        try c.encode(activeTabIndex, forKey: .activeTabIndex)
    }
}

/// One sidebar favorite. Folder reference is stored as a security-scoped
/// bookmark like `PaneState.folderBookmark`; `fallbackPath` is the raw path
/// at the time of save, used only to display a stale entry when bookmark
/// resolution fails (e.g. the folder was deleted on disk).
struct Favorite: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    /// User-editable display name. Defaults to the folder's last path
    /// component on creation; Rename overwrites it.
    var label: String
    var bookmark: Data?
    var fallbackPath: String?

    init(id: UUID = UUID(), label: String, bookmark: Data? = nil, fallbackPath: String? = nil) {
        self.id = id
        self.label = label
        self.bookmark = bookmark
        self.fallbackPath = fallbackPath
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, bookmark, fallbackPath
    }

    /// Hand-rolled so a favorite that lost its `id` or `label` (a future
    /// schema bump, a hand-edited file, a truncated write) decodes with
    /// sensible defaults instead of throwing. Throwing here is what makes
    /// `WorkspaceState`'s `try?`-wrapped favorites decode drop the *entire*
    /// list, so a single malformed entry must never abort.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallbackPath = c.decode(String?.self, forKey: .fallbackPath, default: nil)
        self.init(
            id: c.decode(UUID.self, forKey: .id, default: UUID()),
            label: c.decode(String.self, forKey: .label,
                            default: fallbackPath.map { ($0 as NSString).lastPathComponent } ?? "Favorite"),
            bookmark: c.decode(Data?.self, forKey: .bookmark, default: nil),
            fallbackPath: fallbackPath
        )
    }
}

/// Window-level state that survives an app restart, scoped to a single
/// project. Always carries four pane states even when `layout` shows
/// fewer panes — growing the layout (e.g. single → 4-pane) restores the
/// previously-loaded folders rather than reverting to empty. Favorites
/// live a level up on `WorkspaceState` because they're cross-project.
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

    /// Force `panes` to exactly four records: pad short arrays with empty
    /// panes, truncate long ones. The "always four panes in storage" rule
    /// is load-bearing for the layout shrink/grow logic, so a truncated or
    /// hand-edited state.json with a non-4 array must normalize here rather
    /// than reach the memberwise `precondition` and crash a load that the
    /// `loadState()` contract says can never throw.
    private static func normalizedToFour(_ panes: [PaneState]) -> [PaneState] {
        if panes.count == 4 { return panes }
        if panes.count > 4 { return Array(panes.prefix(4)) }
        return panes + Array(repeating: PaneState(), count: 4 - panes.count)
    }

    private enum CodingKeys: String, CodingKey {
        case layout, focusedPaneIndex, panes
    }

    /// Hand-rolled so (a) a future added field defaults instead of failing
    /// the decode of every old file, and (b) the pane array is normalized to
    /// exactly four at the decode boundary. Mirrors how
    /// `WorkspaceState.init(from:)` already pads its legacy pane array.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let panes = c.decodeArrayReplacingInvalid(PaneState.self, forKey: .panes, default: PaneState()) ?? []
        if c.contains(.panes), panes.count != 4 { StateDecodingRecovery.record(in: decoder) }
        self.init(
            layout: c.decode(PaneLayout.self, forKey: .layout, default: .four),
            focusedPaneIndex: c.decode(Int.self, forKey: .focusedPaneIndex, default: 0),
            panes: Self.normalizedToFour(panes)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(layout, forKey: .layout)
        try c.encode(focusedPaneIndex, forKey: .focusedPaneIndex)
        try c.encode(panes, forKey: .panes)
    }
}

/// One named workspace. Carries a `WindowState` that fully describes the
/// pane/tab arrangement when this project is active. Switching projects
/// snapshots the outgoing project's `state` and applies the incoming
/// project's `state` to fresh pane VMs.
struct Project: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var state: WindowState

    init(id: UUID = UUID(), name: String, state: WindowState = .empty) {
        self.id = id
        self.name = name
        self.state = state
    }
}

/// User-facing colour scheme preference. Persisted as a stable raw
/// string so the JSON survives a Swift enum reorder; `system` means
/// "follow macOS Appearance" by binding `.preferredColorScheme(nil)`.
enum ColorSchemeOption: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark
}

/// Workspace-level user settings. Lives next to favourites and the
/// project list because it's cross-project; defaults are written
/// through `WorkspaceState.init(from:)`'s `decodeIfPresent` so old
/// `state.json` files come back without a re-seed pop.
struct WorkspaceSettings: Codable, Equatable, Sendable {
    var colorScheme: ColorSchemeOption
    /// Per-action user overrides for the customisable shortcut set.
    /// Missing entries inherit `ShortcutAction.defaultBinding`. The
    /// menu wiring resolves the live binding via
    /// `WorkspaceSettings.binding(for:)` rather than reading this
    /// dictionary directly.
    var shortcutOverrides: [ShortcutAction: ShortcutBinding]
    /// When true, dragging a file out of mq-dir (or copying/moving it
    /// via paste / duplicate / drop) renames any decomposed-Hangul (NFD)
    /// filename to NFC form on disk first, so the receiving app sees a
    /// correctly-composed Korean name instead of `ㅎㅏㄴㄱㅡㄹ`. Defaults
    /// off — it mutates filenames on disk, so it stays opt-in.
    var normalizeHangulOnDragOut: Bool
    var savedSearches: [SavedFileSearch]
    var integrationProvider: WorkspaceProvider

    init(
        colorScheme: ColorSchemeOption = .system,
        shortcutOverrides: [ShortcutAction: ShortcutBinding] = [:],
        normalizeHangulOnDragOut: Bool = false,
        savedSearches: [SavedFileSearch] = [],
        integrationProvider: WorkspaceProvider = .cmux
    ) {
        self.colorScheme = colorScheme
        self.shortcutOverrides = shortcutOverrides
        self.normalizeHangulOnDragOut = normalizeHangulOnDragOut
        self.savedSearches = savedSearches
        self.integrationProvider = integrationProvider
    }

    /// Live binding for `action` — user override if present,
    /// `defaultBinding` otherwise. Single source of truth for both
    /// the menu attach and the Settings row preview.
    func binding(for action: ShortcutAction) -> ShortcutBinding {
        shortcutOverrides[action] ?? action.defaultBinding
    }

    private enum CodingKeys: String, CodingKey {
        case colorScheme
        case shortcutOverrides
        case normalizeHangulOnDragOut
        case savedSearches
        case integrationProvider
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let colorScheme = c.decode(ColorSchemeOption.self, forKey: .colorScheme, default: .system)
        let normalizeHangulOnDragOut = c.decode(Bool.self, forKey: .normalizeHangulOnDragOut, default: false)

        // Decode shortcutOverrides per-entry through an AnyCodingKey
        // container so a future build's added action (or a renamed
        // case) doesn't take the whole override dictionary down with
        // it on a downgrade — known keys still decode, unknown keys
        // skip silently.
        var overrides: [ShortcutAction: ShortcutBinding] = [:]
        if let overrideContainer = try? c.nestedContainer(
            keyedBy: AnyCodingKey.self,
            forKey: .shortcutOverrides
        ) {
            for key in overrideContainer.allKeys {
                guard let action = ShortcutAction(rawValue: key.stringValue) else { continue }
                if let binding = try? overrideContainer.decode(ShortcutBinding.self, forKey: key) {
                    overrides[action] = binding
                }
            }
        }

        self.init(
            colorScheme: colorScheme,
            shortcutOverrides: overrides,
            normalizeHangulOnDragOut: normalizeHangulOnDragOut,
            savedSearches: c.decodeArraySkippingInvalid(SavedFileSearch.self, forKey: .savedSearches) ?? [],
            integrationProvider: c.decode(WorkspaceProvider.self, forKey: .integrationProvider, default: .cmux)
        )
    }
}

/// Generic string-keyed `CodingKey` used to walk an arbitrary
/// JSON object's keys without committing to a fixed enum. Used by
/// `WorkspaceSettings.init(from:)` so a per-entry decode can skip
/// unknown action names instead of failing the entire dictionary.
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(intValue: Int) { return nil }
    init(stringValue: String) { self.stringValue = stringValue }
}

/// Top-level persisted state. Holds cross-project surface (favorites)
/// alongside the project list and which one is active. Old `state.json`
/// files from before this struct existed get migrated by the custom
/// decoder into a single "Default" project so users don't lose state.
struct WorkspaceState: Codable, Equatable, Sendable {
    var favorites: [Favorite]
    /// Distinguishes "user has explicitly emptied favorites" from "first
    /// launch / pre-favorites schema." When false, the sidebar seeds the
    /// six home subdirectories and flips the flag so we don't re-seed
    /// after the user clears the list.
    var favoritesSeeded: Bool
    var activeProjectID: UUID
    var projects: [Project]
    var settings: WorkspaceSettings

    init(
        favorites: [Favorite] = [],
        favoritesSeeded: Bool = false,
        activeProjectID: UUID,
        projects: [Project],
        settings: WorkspaceSettings = WorkspaceSettings()
    ) {
        precondition(!projects.isEmpty, "WorkspaceState always carries at least one project")
        self.favorites = favorites
        self.favoritesSeeded = favoritesSeeded
        self.activeProjectID = activeProjectID
        self.projects = projects
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case favorites, favoritesSeeded, activeProjectID, projects, settings
        // Legacy keys (pre-projects schema)
        case layout, focusedPaneIndex, panes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // New shape — has a top-level `projects` array. Discriminate by key
        // presence (not by a successful atomic decode) so a single corrupt
        // project element no longer drops us into the legacy branch and
        // loses every other project. Each element is decoded individually
        // and bad ones are skipped, mirroring the shortcutOverrides pattern.
        if c.contains(.projects) {
            let rawProjects = c.decodeArraySkippingInvalid(Project.self, forKey: .projects) ?? []
            let projects = rawProjects.isEmpty ? [Project(name: "Default")] : rawProjects
            let active = (try? c.decode(UUID.self, forKey: .activeProjectID)) ?? projects.first!.id
            // Tolerate dangling activeProjectID — fall back to the first
            // project so a corrupt write can't lock the user out.
            let resolved = projects.contains(where: { $0.id == active }) ? active : projects.first!.id
            self.init(
                favorites: c.decodeArraySkippingInvalid(Favorite.self, forKey: .favorites) ?? [],
                favoritesSeeded: c.decode(Bool.self, forKey: .favoritesSeeded, default: false),
                activeProjectID: resolved,
                projects: projects,
                settings: c.decode(WorkspaceSettings.self, forKey: .settings, default: WorkspaceSettings())
            )
            return
        }

        // Legacy shape — top-level WindowState fields. Wrap as a single
        // "Default" project so the user's last layout/panes survive the
        // upgrade unchanged.
        let favorites = c.decodeArraySkippingInvalid(Favorite.self, forKey: .favorites) ?? []
        let seeded = c.decode(Bool.self, forKey: .favoritesSeeded, default: false)

        let migrated = Project(
            name: "Default",
            state: try WindowState(from: decoder)
        )
        self.init(
            favorites: favorites,
            favoritesSeeded: seeded,
            activeProjectID: migrated.id,
            projects: [migrated]
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(favorites, forKey: .favorites)
        try c.encode(favoritesSeeded, forKey: .favoritesSeeded)
        try c.encode(activeProjectID, forKey: .activeProjectID)
        try c.encode(projects, forKey: .projects)
        try c.encode(settings, forKey: .settings)
    }

    static var empty: WorkspaceState {
        let project = Project(name: "Default")
        return WorkspaceState(
            favorites: [],
            favoritesSeeded: false,
            activeProjectID: project.id,
            projects: [project]
        )
    }
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
        #if DEBUG
        if let directory = ProcessInfo.processInfo.environment["MQDIR_TEST_STATE_DIR"], !directory.isEmpty {
            try self.init(stateURL: URL(fileURLWithPath: directory).appendingPathComponent("state.json"), fileManager: fileManager)
            return
        }
        #endif
        let supportRoot = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleDir = supportRoot.appendingPathComponent("com.mqdir.app", isDirectory: true)
        try self.init(stateURL: bundleDir.appendingPathComponent("state.json", isDirectory: false), fileManager: fileManager)
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
    ///
    /// When decoding fails or repairs damaged pane/tab records, the original
    /// is copied aside to
    /// `state.corrupt-<timestamp>.json` before returning nil. Otherwise the
    /// very next debounced `saveState` overwrites the only copy of the
    /// user's broken-but-recoverable state, and a support request has
    /// nothing to inspect.
    func loadState(onRecovery: ((String) -> Void)? = nil) -> WorkspaceState? {
        guard fileManager.fileExists(atPath: stateURL.path) else { return nil }
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        let recovery = StateDecodingRecovery()
        let decoder = JSONDecoder()
        decoder.userInfo[StateDecodingRecovery.key] = recovery
        do {
            let state = try decoder.decode(WorkspaceState.self, from: data)
            if recovery.repaired {
                let backedUp = backUpCorruptStateFile()
                onRecovery?("Some saved panes or tabs were damaged. Your other folders and tabs were restored. "
                    + (backedUp ? "A copy of the original state was saved for recovery."
                       : "The original state could not be backed up."))
            }
            return state
        } catch {
            let backedUp = backUpCorruptStateFile()
            onRecovery?("Your saved workspace could not be read. "
                + (backedUp ? "A copy was saved for recovery. The app will open a new workspace."
                   : "The original state could not be backed up. The app will open a new workspace."))
            return nil
        }
    }

    /// Preserve the source before a recovered/default state replaces it.
    private func backUpCorruptStateFile() -> Bool {
        let stamp = Self.corruptBackupTimestampFormatter.string(from: Date())
        let backupURL = stateURL
            .deletingLastPathComponent()
            .appendingPathComponent("state.corrupt-\(stamp)-\(UUID().uuidString).json", isDirectory: false)
        do {
            try fileManager.copyItem(at: stateURL, to: backupURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            return true
        } catch {
            FileHandle.standardError.write(Data(
                "[mq-dir persist] state backup failed: \(error)\n".utf8
            ))
            return false
        }
    }

    /// Filesystem-safe timestamp (no colons) for the corrupt-file side-car.
    private static let corruptBackupTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    /// Writes the state atomically. Throws so the caller (typically a
    /// debounced save) can log a failure without crashing.
    ///
    /// Lock the file down to owner-only after writing — the JSON contains
    /// security-scoped bookmarks (and, in App Store mode, what amount to
    /// authentication tokens for each remembered folder), so the default
    /// umask (often 0644) is too permissive for a multi-user box.
    /// Permission failures are non-fatal: the write succeeded, the file
    /// is just slightly more readable than ideal.
    func saveState(_ state: WorkspaceState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: [.atomic])
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: stateURL.path
            )
        } catch {
            // Non-fatal: the write succeeded, the file is just more readable
            // than ideal. Log it instead of swallowing so a multi-user box
            // with surprising permissions leaves a trail.
            FileHandle.standardError.write(Data(
                "[mq-dir persist] could not tighten state.json permissions to 0600 (\(error))\n".utf8
            ))
        }
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
