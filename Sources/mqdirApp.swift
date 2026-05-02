import AppKit
import SwiftUI

@main
struct mqdirApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Forward NSApplication's willTerminate to our internal notification
        // so MainWindowView can flush a synchronous save before exit.
        // Doing this in App.init keeps the wiring close to the lifecycle
        // that depends on it, and avoids touching AppDelegate's existing
        // M0-era responsibilities.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .mqdirAppWillTerminate, object: nil)
        }
    }

    var body: some Scene {
        WindowGroup("mq-dir") {
            MainWindowView()
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
        .commands {
            MenuCommands()
        }
    }
}
