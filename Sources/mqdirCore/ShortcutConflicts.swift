import Foundation

enum ShortcutConflicts {
    static func reservedName(for binding: ShortcutBinding) -> String? {
        let fixed: [(ShortcutBinding, String)] = [
            (.init(key: .character("n"), modifiers: [.command, .shift]), "New Folder"),
            (.init(key: .upArrow, modifiers: []), "Navigate Up"),
            (.init(key: .downArrow, modifiers: []), "Navigate Down"),
            (.init(key: .leftArrow, modifiers: []), "Collapse Folder"),
            (.init(key: .rightArrow, modifiers: []), "Expand Folder"),
            (.init(key: .tab, modifiers: []), "Move Keyboard Focus"),
            (.init(key: .character(" "), modifiers: []), "Quick Look"),
            (.init(key: .character("x"), modifiers: .command), "Cut"),
            (.init(key: .character("c"), modifiers: .command), "Copy"),
            (.init(key: .character("v"), modifiers: .command), "Paste"),
            (.init(key: .character("a"), modifiers: .command), "Select All"),
            (.init(key: .character("q"), modifiers: .command), "Quit"),
            (.init(key: .character(","), modifiers: .command), "Settings"),
            (.init(key: .character("h"), modifiers: .command), "Hide"),
            (.init(key: .character("m"), modifiers: .command), "Minimize"),
            (.init(key: .character("z"), modifiers: .command), "Undo text editing"),
            (.init(key: .character("z"), modifiers: [.command, .shift]), "Redo text editing"),
            (.init(key: .character("t"), modifiers: [.command, .shift]), "Reopen Closed Tab"),
            (.init(key: .character("["), modifiers: [.command, .shift]), "Previous Tab"),
            (.init(key: .character("]"), modifiers: [.command, .shift]), "Next Tab"),
            (.init(key: .character("c"), modifiers: [.command, .option]), "Copy File Path"),
            (.init(key: .character("c"), modifiers: [.command, .option, .shift]), "Copy Folder Path"),
            (.init(key: .return, modifiers: []), "Open Selected"),
            (.init(key: .return, modifiers: .command), "Open in New Tab"),
        ]
        if let match = fixed.first(where: { $0.0 == binding }) { return match.1 }
        for number in 1...9 where binding == .init(key: .character(Character(String(number))), modifiers: .command) {
            return "Select Tab \(number)"
        }
        for number in 1...4 where binding == .init(key: .character(Character(String(number))), modifiers: [.command, .option]) {
            return "Focus Pane \(number)"
        }
        return nil
    }
}
