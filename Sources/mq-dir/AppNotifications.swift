import Foundation

/// Typed menu/keyboard command, dispatched through the single
/// `.mqdirCommand` notification instead of the old per-command
/// `Notification.Name` fan-out. Posting goes through one helper
/// (`AppCommand.post()`); MainWindowView's receiver modifiers each switch
/// on this enum from one publisher. A typo'd command is now a compile
/// error, and adding a command is "add a case + handle it in the modifier
/// that owns it" (the switches are exhaustive — the compiler flags a case
/// no modifier handles).
///
/// Only *user-command* notifications (menu / keyboard → focused-pane
/// actions) live here. Broadcast events keep their own dedicated names —
/// see the `Notification.Name` extension below for which stayed and why.
enum AppCommand: Equatable {
    // MARK: File menu / navigation (handled by NavigationNotifications)
    case openFolder
    case openSelected
    case revealSelected
    case reload
    case parentFolder
    case toggleHiddenFiles
    case goBack
    case goForward
    case focusSearch
    /// Add the focused pane's current folder to the sidebar Favorites list.
    case addCurrentFolderToFavorites
    /// Toggle the right-side preview panel for the focused pane's active tab.
    case togglePreview
    /// View → As List / As Tree.
    case setViewModeList
    case setViewModeTree

    // MARK: Edit menu — pasteboard / selection (EditMenuNotifications)
    case selectAll
    case copy
    case cut
    case paste
    case delete
    /// Edit → Delete Immediately (⌘⌥⌫) — destructive NSAlert, bypasses trash.
    case permanentDelete

    // MARK: Edit menu — file-selection actions (EditFileActionsNotifications)
    case openWithDefaultApp
    case duplicate
    case copyFilePaths
    /// Copies the *current folder* path (not the selection).
    case copyFolderPath
    case copyName
    case rename

    // MARK: Tabs in the focused pane (TabNotifications)
    case newTab
    case closeTab
    case reopenClosedTab
    case nextTab
    case previousTab
    /// Posted by ⌘1…⌘9. Payload is the zero-based tab index; the focused
    /// pane silently ignores out-of-range values.
    case selectTab(index: Int)
    /// "Open in new tab" — ⌘-click / ⌘-double-click on a folder row in
    /// tree or list view, or ⌘-click on a cmux row. Appends a new tab in
    /// the *focused* pane pointing at `url`. Mirrors Finder's
    /// ⌘-click-on-folder behavior.
    case openURLInNewTab(url: URL)

    // MARK: Pane focus (PaneFocusNotifications)
    /// Posted by Window → Focus Pane N (⌥⌘1–4). Payload is the zero-based
    /// pane index; receivers ignore values outside the active layout's
    /// pane count.
    case focusPane(index: Int)

    /// userInfo key under which the command travels on `.mqdirCommand`.
    fileprivate static let userInfoKey = "command"

    /// Post this command on the single `.mqdirCommand` channel.
    func post() {
        NotificationCenter.default.post(
            name: .mqdirCommand,
            object: nil,
            userInfo: [AppCommand.userInfoKey: self]
        )
    }

    /// Pull the typed command back out of a received notification.
    static func from(_ notification: Notification) -> AppCommand? {
        notification.userInfo?[userInfoKey] as? AppCommand
    }
}

extension Notification.Name {
    /// Single channel carrying every typed `AppCommand` in `userInfo`.
    /// Replaces the ~30 per-command `mqdir*Requested` names.
    static let mqdirCommand = Notification.Name("mqdir.command")

    // MARK: - Non-command notifications (deliberately NOT folded into AppCommand)
    //
    // These are broadcast/lifecycle events, not menu→focused-pane commands,
    // so they keep their own dedicated names:
    //
    // • `mqdirFileSystemChanged` — a fan-OUT broadcast: every open tab in
    //   every pane reloads. Posted from AppKit drag/drop bridges and the
    //   VM's own file-operation paths, not from the menu. Not a "focused
    //   pane, do X" command.
    // • `mqdirAppWillTerminate` — app-lifecycle flush posted by `mqdirApp`
    //   from the OS termination hook, not a user action.

    /// FSEvents lands later; until then drag/drop + file ops post this and
    /// every open tab refetches its folder.
    static let mqdirFileSystemChanged = Notification.Name("mqdir.fileSystemChanged")
    /// Posted by `mqdirApp` when the OS notifies us of imminent termination,
    /// so the active window can flush a synchronous save before exit.
    static let mqdirAppWillTerminate = Notification.Name("mqdir.appWillTerminate")
}

/// Scoped change notifications; legacy senders without folders still refresh all.
enum FileSystemChange {
    static func post(folders: [URL]) {
        NotificationCenter.default.post(name: .mqdirFileSystemChanged, object: nil,
            userInfo: ["folders": Array(Set(folders))])
    }

    static func folders(in notification: Notification) -> [URL]? {
        notification.userInfo?["folders"] as? [URL]
    }
}

@MainActor
enum ExternalFolderRequests {
    private static var pending: [URL] = []
    static let changed = Notification.Name("mqdir.externalFolderRequests")
    static func enqueue(_ urls: [URL]) {
        pending.append(contentsOf: urls.filter(\.isFileURL))
        NotificationCenter.default.post(name: changed, object: nil)
    }
    static func consume() -> [URL] {
        defer { pending.removeAll() }
        return pending
    }
}
