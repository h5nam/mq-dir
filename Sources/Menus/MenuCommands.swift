import SwiftUI

struct MenuCommands: Commands {
    @State private var showHiddenFiles = false

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { stub("File → New Window") }
                .keyboardShortcut("n", modifiers: .command)
            Divider()
            Button("Open Folder…") { stub("File → Open Folder") }
                .keyboardShortcut("o", modifiers: .command)
            Button("Close") { stub("File → Close") }
                .keyboardShortcut("w", modifiers: .command)
            Divider()
            Button("Reveal in Finder") { stub("File → Reveal in Finder") }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Toggle("Show Hidden Files", isOn: $showHiddenFiles)
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
}
