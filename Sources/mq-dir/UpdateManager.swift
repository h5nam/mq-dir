import AppKit
import Combine
import Foundation
import Sparkle

/// Drives Sparkle on behalf of the UI.
///
/// Sparkle's standard updater controller silently checks the appcast at the
/// configured interval; we observe the result via `SPUUpdaterDelegate` and
/// surface a single `@Published var updateAvailable` flag. The sidebar
/// renders its update button only while that flag is true; tapping it
/// re-runs `checkForUpdates(_:)` so Sparkle's stock confirm/install dialog
/// drives the actual download + relaunch.
///
/// We deliberately *don't* use a custom user driver yet — Sparkle's stock
/// dialogs already handle progress, errors, and the relaunch prompt; until
/// the UX needs diverge from "show the system flow on click", reinventing
/// that surface area is wasted work.
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    @Published private(set) var updateAvailable: Bool = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var lastCheckDate: Date?

    /// Optional + var because Sparkle's controller takes its delegate at
    /// construction time, but `self` isn't usable until super.init() runs.
    /// We resolve the order by initializing super first, then assigning
    /// the controller with `self` as the delegate. Stays nil entirely
    /// when the public EdDSA key is missing — Sparkle 2 refuses to start
    /// without one and the resulting "updater failed to start" alert is
    /// worse UX than dormant auto-update.
    private var updaterController: SPUStandardUpdaterController?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        #if DEBUG
        if ProcessInfo.processInfo.environment["MQDIR_TEST_STATE_DIR"] != nil { return }
        #endif

        // Mirror availability into the Dock badge so users notice updates
        // even when the sidebar isn't visible. Sparkle's stock UX has no
        // notification surface of its own.
        $updateAvailable
            .receive(on: DispatchQueue.main)
            .sink { available in
                NSApp.dockTile.badgeLabel = available ? "1" : nil
            }
            .store(in: &cancellables)

        let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) ?? ""
        guard !publicKey.isEmpty else { return }

        // Build the controller without auto-starting so we can catch the
        // throw from `start()` ourselves instead of letting Sparkle's
        // standard controller pop its "updater failed to start" alert
        // on every launch of an unsigned dev build.
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        do {
            try controller.updater.start()
            self.updaterController = controller
            // Force a one-shot background check on launch. Sparkle's own
            // scheduler waits for `SUScheduledCheckInterval` to elapse
            // since the last `SULastCheckTime`, which means a new release
            // published right after a check can sit unnoticed for hours.
            // Kicking a background check immediately closes that window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.updaterController?.updater.checkForUpdatesInBackground()
            }
        } catch {
            NSLog("[mq-dir] Sparkle did not start: \(error.localizedDescription) — auto-update disabled for this build.")
            self.updaterController = nil
        }
    }

    /// Manual check entry-point. Bound to the sidebar update button —
    /// triggers the standard Sparkle UI for confirm + install + relaunch.
    @MainActor
    func checkForUpdatesAndShowUI() {
        updaterController?.checkForUpdates(nil)
    }

    /// Background-check entry-point — same as the timer-driven one but
    /// callable from us if we ever add a manual "Check Now" menu item.
    @MainActor
    func checkInBackground() {
        updaterController?.updater.checkForUpdatesInBackground()
    }
}

// MARK: - Sparkle delegate

extension UpdateManager: SPUUpdaterDelegate {
    /// Called whenever Sparkle's background check successfully finds an
    /// appcast item with a higher version than the currently-running app.
    /// We just flip the flag — the sidebar reacts and the user clicks the
    /// button when ready, no surprise modal popups.
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.updateAvailable = true
            self.availableVersion = version
            self.lastCheckDate = Date()
        }
    }

    /// Update was found and either dismissed by the user or installed.
    /// Either way the flag clears so the button hides.
    nonisolated func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        Task { @MainActor in
            self.updateAvailable = false
            self.availableVersion = nil
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.updateAvailable = false
            self.availableVersion = nil
            self.lastCheckDate = Date()
        }
    }
}
