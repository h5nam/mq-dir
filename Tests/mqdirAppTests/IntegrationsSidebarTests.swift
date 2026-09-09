import XCTest

final class IntegrationsSidebarTests: XCTestCase {
    @MainActor
    func testSwitchingProviderDropsLateResults() async throws {
        let started = expectation(description: "old sync started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let model = IntegrationsSidebarModel(provider: .orca) { _, _, _, _ in
            started.fulfill()
            _ = release.wait(timeout: .now() + 3)
            return [IntegrationWorkspace(id: "old", title: "Old", currentDirectory: "/fixture/old")]
        }
        let task = Task { await model.sync() }
        await fulfillment(of: [started], timeout: 2)
        model.provider = .paseo
        release.signal()
        await task.value
        XCTAssertEqual(model.provider, .paseo)
        XCTAssertTrue(model.workspaces.isEmpty)
        XCTAssertFalse(model.isSyncing)
        XCTAssertNil(model.lastSyncDate)
    }
    @MainActor
    func testSessionFoldersAreDeduplicated() async {
        let model = IntegrationsSidebarModel(provider: .claudeDesktop) { _, _, _, _ in
            [
                IntegrationWorkspace(id: "1", title: "New", currentDirectory: "/fixture/project"),
                IntegrationWorkspace(id: "2", title: "Old", currentDirectory: "/fixture/project"),
            ]
        }
        await model.sync()
        XCTAssertEqual(model.workspaces.count, 1)
        XCTAssertEqual(model.workspaces.first?.title, "New")
    }
}
