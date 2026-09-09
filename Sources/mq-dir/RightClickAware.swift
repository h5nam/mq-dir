import AppKit
import SwiftUI

/// Detects right-mouse-down on the wrapped row so SwiftUI's
/// `.contextMenu` can show with the *clicked* row selected, matching
/// Finder. SwiftUI's `.contextMenu` triggers on right-click but
/// doesn't update the underlying selection state — without this the
/// menu items end up operating on whatever row was previously
/// selected, even though the user clearly clicked a different row.
///
/// Pattern: place this `View` behind the row via `.background(...)`.
/// The custom NSView installs an `NSEvent.addLocalMonitorForEvents`
/// callback for `.rightMouseDown` (and ⌃-left-click, the macOS
/// contextual-menu chord) and checks whether the click landed inside
/// its own bounds before invoking the callback. The event is then
/// forwarded unchanged so SwiftUI's `.contextMenu` still pops as
/// usual — we never claim hit-test priority, so we don't risk
/// suppressing the menu the way an overriding `hitTest(_:)` would.
struct RightClickAware: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

final class RightClickView: NSView {
    var onRightClick: (() -> Void)?
    private var monitor: LocalEventMonitor?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else {
            installMonitor()
        }
    }

    deinit {
        // viewDidMoveToWindow handles teardown when SwiftUI removes us
        // from the hierarchy, but make sure deinit also drops the
        // global monitor in case the view is released without first
        // being detached.
        if let monitor { DispatchQueue.main.async { monitor.remove() } }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        let token = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window === window
            else { return event }

            let isContextEvent =
                event.type == .rightMouseDown ||
                (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            guard isContextEvent else { return event }

            let pointInWindow = event.locationInWindow
            let pointInView = self.convert(pointInWindow, from: nil)
            if self.bounds.contains(pointInView) {
                self.onRightClick?()
            }
            return event
        }
        if let token { monitor = LocalEventMonitor(token) }
    }

    private func removeMonitor() {
        if let monitor {
            monitor.remove()
            self.monitor = nil
        }
    }
}


@MainActor
private final class LocalEventMonitor {
    private var token: Any?
    init(_ token: Any) { self.token = token }
    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
