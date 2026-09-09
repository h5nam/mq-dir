import XCTest

@testable import mqdirCore

final class PersistenceRecoveryTests: XCTestCase {
    func testPartialRecoveryBacksUpOriginalBeforeNextSave() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let service = try PersistenceService(stateURL: root.appendingPathComponent("state.json"))
        let original = Data(#"{"panes":[{"tabs":[{"includeHidden":true},17]}]}"#.utf8)
        try original.write(to: service.fileURL)
        var notice: String?
        let state = try XCTUnwrap(service.loadState(onRecovery: { notice = $0 }))
        XCTAssertNotNil(notice)
        try service.saveState(state)
        notice = nil
        XCTAssertNotNil(service.loadState(onRecovery: { notice = $0 }))
        XCTAssertNil(notice, "A successfully repaired file must not warn again on the next launch")
        let backups = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("state.corrupt-") }
        XCTAssertEqual(backups.count, 1)
        if let backup = backups.first { XCTAssertEqual(try Data(contentsOf: backup), original) }
    }

    func testLegacyPaneCountsPreserveRecordsWithoutCrashing() throws {
        for count in 0...8 {
            let panes = Array(repeating: ["includeHidden": true], count: count)
            let data = try JSONSerialization.data(withJSONObject: ["panes": panes])
            let state = try JSONDecoder().decode(WorkspaceState.self, from: data)
            let restored = state.projects[0].state.panes
            XCTAssertEqual(restored.count, 4)
            for index in 0..<min(count, 4) {
                XCTAssertTrue(restored[index].tabs[0].includeHidden)
            }
        }
    }

    func testCorruptTabPreservesNeighborsAndActivePosition() throws {
        let data = Data(#"{"tabs":[{"includeHidden":true},17,{"previewVisible":true}],"activeTabIndex":2}"#.utf8)
        let pane = try JSONDecoder().decode(PaneState.self, from: data)
        XCTAssertEqual(pane.tabs.count, 3)
        guard pane.tabs.count == 3 else { return }
        XCTAssertTrue(pane.tabs[0].includeHidden)
        XCTAssertEqual(pane.tabs[1], TabState())
        XCTAssertTrue(pane.tabs[2].previewVisible)
        XCTAssertEqual(pane.activeTabIndex, 2)
    }

    func testCorruptPanePreservesLayoutPositionsInBothSchemas() throws {
        let panes: [Any] = [["includeHidden": true], NSNull(), ["previewVisible": true]]
        let data = try JSONSerialization.data(withJSONObject: ["panes": panes])
        let current = try JSONDecoder().decode(WindowState.self, from: data)
        let legacy = try JSONDecoder().decode(WorkspaceState.self, from: data).projects[0].state
        for state in [current, legacy] {
            XCTAssertEqual(state.panes.count, 4)
            XCTAssertTrue(state.panes[0].tabs[0].includeHidden)
            XCTAssertEqual(state.panes[1], PaneState())
            XCTAssertTrue(state.panes[2].tabs[0].previewVisible)
        }
    }

    func testMalformedCurrentTabsDoNotFallBackToLegacyFields() throws {
        let data = Data(#"{"tabs":17,"includeHidden":true}"#.utf8)
        let pane = try JSONDecoder().decode(PaneState.self, from: data)
        XCTAssertEqual(pane, PaneState())
    }
}
