import SwiftUI

struct MenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { stub("File → New Window") }
                .keyboardShortcut("n", modifiers: .command)
            Divider()
            Button("Open Folder...") { post(.mqdirOpenFolderRequested) }
                .keyboardShortcut("o", modifiers: .command)
            Button("Open Selected") { post(.mqdirOpenSelectedRequested) }
                .keyboardShortcut(.return, modifiers: [])
            Button("Close") { stub("File → Close") }
                .keyboardShortcut("w", modifiers: .command)
            Divider()
            Button("Reveal in Finder") { post(.mqdirRevealSelectedRequested) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandGroup(after: .textEditing) {
            Button("Find") { post(.mqdirFocusSearchRequested) }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button("Back") { post(.mqdirGoBackRequested) }
                .keyboardShortcut("[", modifiers: .command)
            Button("Forward") { post(.mqdirGoForwardRequested) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Reload") { post(.mqdirReloadRequested) }
                .keyboardShortcut("r", modifiers: .command)
            Button("Parent Folder") { post(.mqdirParentFolderRequested) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Toggle Hidden Files") { post(.mqdirToggleHiddenFilesRequested) }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Divider()
            Button("As List") { stub("View → As List") }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("As Icons") { stub("View → As Icons") }
                .disabled(true)
        }

        CommandGroup(replacing: .help) {
            Link("mq-dir on GitHub",
                 destination: URL(string: "https://github.com/h5nam/mq-dir")!)
        }
    }

    private func stub(_ label: String) {
        FileHandle.standardError.write(Data("[mq-dir M0 stub] \(label)\n".utf8))
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
