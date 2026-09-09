import AppKit
import QuickLookUI
import SwiftUI

/// Floating Quick Look panel coordinator. Mirrors Finder: select rows,
/// hit space → system Quick Look panel pops up showing the selection
/// (multi-item navigation included via the panel's built-in arrows);
/// hit space again or Esc to dismiss.
///
/// Two paths share this singleton:
///
///   1. The direct `toggle(urls:)` path the file-list `.onKeyPress(.space)`
///      handlers call. This opens/closes the panel imperatively and is
///      the workhorse for the common case.
///   2. The formal first-responder protocol
///      (`acceptsPreviewPanelControl`/`begin`/`end`). SwiftUI views aren't
///      NSResponders in the chain Quick Look queries, so a lightweight
///      `QuickLookPanelBridge` (NSViewRepresentable, below) injects an
///      NSView into the window's responder chain that answers the
///      protocol and forwards ownership here. Adopting the protocol is
///      what makes macOS recognise this window as the Quick Look owner —
///      it gives mq-dir standing in system Quick Look arbitration (so a
///      third-party global Space-tap like "Folder Preview" no longer
///      silently out-ranks us) and lets in-panel Space forwarding behave.
///
/// The protocol path *supplements* the direct path; it does not replace
/// it. `beginPreviewPanelControl` wires this singleton as the panel's
/// dataSource/delegate, `endPreviewPanelControl` clears them.
@MainActor
final class QuickLookManager: NSObject {
    static let shared = QuickLookManager()

    private var urls: [URL] = []

    private override init() { super.init() }

    /// Toggle Quick Look for the given selection. Closes the panel if
    /// it's already open showing the *same* selection; opens (or reloads)
    /// it otherwise. No-op on an empty selection so a stray space-key in
    /// an empty list doesn't pop a blank panel.
    func toggle(urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let panel = QLPreviewPanel.shared() else { return }

        // Compare as Sets: the *same* selection in a different order
        // should toggle the panel closed, not reload it. Order doesn't
        // affect what the user sees (the panel shows the whole set), so
        // an order-only difference is not a new selection.
        if panel.isVisible, Set(self.urls) == Set(urls) {
            panel.close()
            return
        }

        self.urls = urls
        panel.dataSource = self
        panel.delegate = self
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Adopt ownership of the panel on behalf of the responder-chain
    /// bridge: install this singleton as dataSource/delegate and reload
    /// so the current selection renders. Called from
    /// `QuickLookPanelBridge`'s `beginPreviewPanelControl(_:)`.
    func takeOwnership(of panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    /// Relinquish ownership when the panel asks the bridge to end
    /// control. Clears dataSource/delegate so a stale singleton pointer
    /// can't keep the panel alive against a torn-down window.
    func relinquishOwnership(of panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
    }
}

extension QuickLookManager: QLPreviewPanelDataSource {
    // Both QLPreviewPanelDataSource callbacks are documented as being
    // delivered on the main thread (QLPreviewPanel drives its data source
    // from the main run loop), so `assumeIsolated` is a faithful, crash-
    // free assertion of the contract here — it documents the guarantee
    // rather than papering over an off-main hop.
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}

extension QuickLookManager: QLPreviewPanelDelegate {
    // No overrides needed — defaults are correct for our usage.
    // Keeping conformance so we can hook keyboard handlers later
    // (e.g. forward arrow keys back to the underlying file list)
    // without having to re-thread the delegate slot.
}

/// Injects an NSView into the hosting window's responder chain so the
/// window has formal standing in Quick Look's first-responder
/// arbitration. The view answers `acceptsPreviewPanelControl(_:)` /
/// `beginPreviewPanelControl(_:)` / `endPreviewPanelControl(_:)` and
/// forwards panel ownership to `QuickLookManager.shared`.
///
/// Attach once per pane via `.background(QuickLookPanelBridge())`; the
/// view is zero-size and non-interactive (it never claims hit-test
/// priority), it exists purely to sit in the responder chain. The direct
/// `QuickLookManager.shared.toggle(urls:)` path keeps working unchanged —
/// this only adds the protocol surface macOS uses to identify the window
/// as the Quick Look owner.
struct QuickLookPanelBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> QuickLookResponderView {
        QuickLookResponderView()
    }

    func updateNSView(_ nsView: QuickLookResponderView, context: Context) {}
}

final class QuickLookResponderView: NSView {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        MainActor.assumeIsolated { QuickLookManager.shared.takeOwnership(of: panel) }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        MainActor.assumeIsolated { QuickLookManager.shared.relinquishOwnership(of: panel) }
    }
}
