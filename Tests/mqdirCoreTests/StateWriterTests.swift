import XCTest

@testable import mqdirCore

final class StateWriterTests: XCTestCase {
    func testTerminationFlushWaitsForOlderWriteAndLeavesLatestState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = try PersistenceService(stateURL: root.appendingPathComponent("state.json"))
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let olderFinished = DispatchSemaphore(value: 0)
        var older = WorkspaceState.empty
        older.projects[0].name = "older"
        var latest = older
        latest.projects[0].name = "latest"
        let writer = StateWriter { state in
            if state.projects[0].name == "older" {
                started.signal()
                guard release.wait(timeout: .now() + 3) == .success else { throw CocoaError(.fileWriteUnknown) }
            }
            try persistence.saveState(state)
            if state.projects[0].name == "older" { olderFinished.signal() }
        }
        writer.enqueue(older)
        XCTAssertEqual(started.wait(timeout: .now() + 3), .success)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { release.signal() }
        try writer.flush(latest)
        XCTAssertEqual(olderFinished.wait(timeout: .now() + 3), .success)
        XCTAssertEqual(persistence.loadState(), latest)
    }

    func testFailedWriteDoesNotPreventLaterFlush() throws {
        let writer = StateWriter { state in
            if state.projects[0].name == "fail" { throw CocoaError(.fileWriteNoPermission) }
        }
        var broken = WorkspaceState.empty
        broken.projects[0].name = "fail"
        writer.enqueue(broken)
        XCTAssertThrowsError(try writer.flush(broken))
        XCTAssertNoThrow(try writer.flush(.empty))
    }
}
