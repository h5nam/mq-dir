import AppKit

/// Restores ⌘X / ⌘C / ⌘V / ⌘A / ⌘Z / ⇧⌘Z inside app-modal windows — the
/// Open Folder panel, its ⇧⌘G "Go to the folder" sheet, alerts.
///
/// `MenuCommands` replaces the stock Edit items with SwiftUI buttons so the
/// same keys act on files in the panes. While `runModal` is up AppKit
/// disables those buttons (their target isn't in the modal window) yet the
/// menu still claims the key equivalent, so the text field never sees it:
/// ⌘V in the Open panel's path sheet silently did nothing. During a modal
/// session, send the standard action to the key window's responder chain
/// instead — exactly what the stock Edit menu would have done. The Open
/// panel runs out of process; its host window (`NSRemoteOpenPanel`) takes
/// `paste:` / `undo:` / `redo:` and forwards them, and gets first try at
/// the raw key equivalent for the rest.
@MainActor
enum ModalEditKeys {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.modalWindow != nil, let action = action(for: event),
                let window = NSApp.keyWindow
            else { return event }
            if window.firstResponder?.tryToPerform(action, with: nil) == true
                || window.performKeyEquivalent(with: event) {
                return nil
            }
            return event
        }
    }

    private static func action(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (key(of: event), modifiers) {
        case ("x", .command): return #selector(NSText.cut(_:))
        case ("c", .command): return #selector(NSText.copy(_:))
        case ("v", .command): return #selector(NSText.paste(_:))
        case ("a", .command): return #selector(NSText.selectAll(_:))
        case ("z", .command): return Selector(("undo:"))
        case ("z", [.command, .shift]): return Selector(("redo:"))
        default: return nil
        }
    }

    /// The letter as typed, falling back to the physical ANSI key when the
    /// active input source reports a non-Latin character (e.g. Hangul).
    private static func key(of event: NSEvent) -> String? {
        if let characters = event.charactersIgnoringModifiers?.lowercased(),
            characters.count == 1, characters.first?.isASCII == true {
            return characters
        }
        let ansi: [UInt16: String] = [7: "x", 8: "c", 9: "v", 0: "a", 6: "z"]
        return ansi[event.keyCode]
    }
}
