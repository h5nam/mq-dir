import XCTest
@testable import mqdirCore

final class LayoutAndShortcutTests: XCTestCase {
    func testThreePaneKeepsLegacyTwoVerticalRawValue() throws {
        XCTAssertEqual(try JSONDecoder().decode(PaneLayout.self, from: Data("3".utf8)), .twoV)
        XCTAssertEqual(PaneLayout.three.paneCount, 3)
        XCTAssertEqual(try JSONDecoder().decode(PaneLayout.self, from: JSONEncoder().encode(PaneLayout.three)), .three)
    }
    func testReservedClipboardAndTabShortcutsCannotBeReassigned() {
        XCTAssertNotNil(ShortcutConflicts.reservedName(for: .init(key: .character("c"), modifiers: .command)))
        XCTAssertNotNil(ShortcutConflicts.reservedName(for: .init(key: .character("4"), modifiers: [.command, .option])))
        XCTAssertNil(ShortcutConflicts.reservedName(for: .init(key: .functionKey(8), modifiers: [])))
        for action in ShortcutAction.allCases { XCTAssertNil(ShortcutConflicts.reservedName(for: action.defaultBinding)) }
    }
}
