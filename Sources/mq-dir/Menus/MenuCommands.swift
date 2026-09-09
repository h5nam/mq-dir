import AppKit
import SwiftUI

struct MenuCommands: Commands {
    @ObservedObject private var fileWork = FileWorkCenter.shared
    @ObservedObject var workspace: WorkspaceManager

    /// Resolved binding for a customisable action — user override
    /// from `WorkspaceSettings`, falling back to the default. Used
    /// by every menu item whose shortcut is exposed in Settings →
    /// Shortcuts so the menu re-attaches when the user remaps.
    private func binding(_ action: ShortcutAction) -> ShortcutBinding {
        workspace.workspace.settings.binding(for: action)
    }

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
                    editor.undoManager?.undo()
                } else if let job = fileWork.lastUndoableJob {
                    fileWork.undo(job)
                }
            }
            .keyboardShortcut("z", modifiers: .command)
            Button("Redo text editing") {
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
                    editor.undoManager?.redo()
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { post(.newTab) }
                .keyboardShortcut(binding(.newTab))
            Divider()
            Button("Open Folder...") { post(.openFolder) }
                .keyboardShortcut(binding(.openFolder))
            Button("Open Selected") { post(.openSelected) }
                .keyboardShortcut(.return, modifiers: [])
            Button("Close Tab") { post(.closeTab) }
                .keyboardShortcut(binding(.closeTab))
            Button("Reopen Closed Tab") { post(.reopenClosedTab) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            // ⌘⇧R is now Edit → Rename (Eagle convention). Reveal in
            // Finder loses its shortcut and lives on the right-click
            // menu + the menu bar entry; the alternative would be
            // double-binding ⌘⇧R, which silently breaks unrelated
            // menu shortcut routing on macOS.
            Button("Reveal in Finder") { post(.revealSelected) }
                .keyboardShortcut(binding(.revealInFinder))
            Divider()
            Button("Add to Favorites") { post(.addCurrentFolderToFavorites) }
                .keyboardShortcut(binding(.addToFavorites))
        }

        // Replace the system pasteboard group entirely so file-level
        // Copy/Paste/Delete and Select All actually run on the focused
        // pane's selection. Each item routes to a `mqdir*` notification
        // when the first responder isn't a text view; if a TextField
        // (search box, inline rename) IS the first responder we
        // forward to its native AppKit action so the user's expected
        // text-Cmd+C / Cmd+V / Cmd+A still works there.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { dispatch(text: #selector(NSText.cut(_:)), file: .cut) }
                .keyboardShortcut("x", modifiers: .command)
            Button("Copy") { dispatch(text: #selector(NSText.copy(_:)), file: .copy) }
                .keyboardShortcut("c", modifiers: .command)
            Button("Paste") { dispatch(text: #selector(NSText.paste(_:)), file: .paste) }
                .keyboardShortcut("v", modifiers: .command)
            // ⌘⌫ matches Finder's "Move to Trash". The dispatch helper
            // forwards plain Delete (text-edit selector) when a TextField
            // is the first responder, but ⌘⌫ in a TextField is rare on
            // macOS and harmlessly invokes NSText.delete(_:) on a
            // selected range.
            Button("Move to Trash") { dispatch(text: #selector(NSText.delete(_:)), file: .delete) }
                .keyboardShortcut(binding(.moveToTrash))
            // Permanent delete bypasses the trash — confirmed via
            // NSAlert in the focused pane's view model.
            Button("Delete Immediately\u{2026}") { post(.permanentDelete) }
                .keyboardShortcut(binding(.deleteImmediately))
            Divider()
            Button("Select All") { dispatch(text: #selector(NSText.selectAll(_:)), file: .selectAll) }
                .keyboardShortcut("a", modifiers: .command)
        }

        // File-selection actions tucked into the Edit menu just below
        // the pasteboard group. Eagle / Finder parity for the shortcuts
        // power users hit reflexively.
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Open with Default App") { post(.openWithDefaultApp) }
                .keyboardShortcut(binding(.openWithDefaultApp))
            Button("Duplicate") { post(.duplicate) }
                .keyboardShortcut(binding(.duplicate))
            Divider()
            Button("Copy File Path") { post(.copyFilePaths) }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Copy Folder Path") { post(.copyFolderPath) }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            Button("Copy Name") { post(.copyName) }
            Divider()
            Button("Rename") { post(.rename) }
                .keyboardShortcut(binding(.rename))
        }

        CommandGroup(after: .textEditing) {
            Button("Find") { post(.focusSearch) }
                .keyboardShortcut(binding(.find))
            Button("Show Preview") { post(.togglePreview) }
                .keyboardShortcut(binding(.togglePreview))
        }

        CommandGroup(after: .toolbar) {
            Button("Back") { post(.goBack) }
                .keyboardShortcut(binding(.back))
            Button("Forward") { post(.goForward) }
                .keyboardShortcut(binding(.forward))
            Button("Reload") { post(.reload) }
                .keyboardShortcut(binding(.reload))
            Button("Parent Folder") { post(.parentFolder) }
                .keyboardShortcut(binding(.parentFolder))
            Button("Toggle Hidden Files") { post(.toggleHiddenFiles) }
                .keyboardShortcut(binding(.toggleHiddenFiles))
            Divider()
            // As List / As Tree intentionally have no keyboard shortcut:
            // ⌥⌘1–4 are claimed by Window → Focus Pane and view-mode
            // toggling is rare enough to live on the menu and the
            // toolbar's segmented control.
            Button("As List") { post(.setViewModeList) }
            Button("As Tree") { post(.setViewModeTree) }
        }

        // Tab navigation lives under the standard Window menu, matching
        // Safari/Finder where ⌘⇧[ ⌘⇧] move between tabs and ⌘1…⌘9 jump
        // to a specific one. We attach `after: .windowArrangement` so it
        // appears below the system "Bring All to Front" entry.
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Show Next Tab") { post(.nextTab) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Show Previous Tab") { post(.previousTab) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
            selectTabButton(index: 0, key: "1")
            selectTabButton(index: 1, key: "2")
            selectTabButton(index: 2, key: "3")
            selectTabButton(index: 3, key: "4")
            selectTabButton(index: 4, key: "5")
            selectTabButton(index: 5, key: "6")
            selectTabButton(index: 6, key: "7")
            selectTabButton(index: 7, key: "8")
            selectTabButton(index: 8, key: "9")
            Divider()
            // ⌥⌘1–4 move keyboard focus between the four panes in the
            // current layout. Indices outside the active layout's pane
            // count are silently dropped by MainWindowView.
            focusPaneButton(index: 0, key: "1")
            focusPaneButton(index: 1, key: "2")
            focusPaneButton(index: 2, key: "3")
            focusPaneButton(index: 3, key: "4")
        }

        CommandGroup(replacing: .help) {
            Link("mq-dir on GitHub",
                 destination: URL(string: "https://github.com/h5nam/mq-dir")!)
        }
    }

    private func selectTabButton(index: Int, key: KeyEquivalent) -> some View {
        Button("Select Tab \(index + 1)") {
            post(.selectTab(index: index))
        }
        .keyboardShortcut(key, modifiers: .command)
    }

    private func focusPaneButton(index: Int, key: KeyEquivalent) -> some View {
        Button("Focus Pane \(index + 1)") {
            post(.focusPane(index: index))
        }
        .keyboardShortcut(key, modifiers: [.command, .option])
    }



    private func post(_ command: AppCommand) {
        command.post()
    }

    /// Edit-menu dispatcher. Only forward to the system text selector
    /// when the focused responder is genuinely editing text — i.e. the
    /// NSTextField field editor that powers the search box, inline
    /// rename, etc. A plain `responder is NSText` check used to fire
    /// here too, but `QLPreviewView` installs its own read-only
    /// NSTextView as first responder once it appears, so ⌘C on a
    /// .docx (or any non-markdown file with a text-rendered Quick
    /// Look preview) was silently sent to that view as a no-op
    /// instead of running our file-level copy. `isFieldEditor` is
    /// the load-bearing filter — only true for the field editor an
    /// NSTextField installs while the user is typing.
    private func dispatch(text selector: Selector, file command: AppCommand) {
        let responder = NSApp.keyWindow?.firstResponder
        if let textView = responder as? NSTextView, textView.isFieldEditor {
            NSApp.sendAction(selector, to: responder, from: nil)
        } else {
            post(command)
        }
    }
}
