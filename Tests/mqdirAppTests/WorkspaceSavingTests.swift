import XCTest

final class WorkspaceSavingTests: XCTestCase {
    @MainActor
    func testDelayedSnapshotCannotOverwriteNewlyActiveProject() {
        let first = Project(name: "first")
        let second = Project(name: "second")
        let state = WorkspaceState(favoritesSeeded: true, activeProjectID: first.id, projects: [first, second])
        let manager = WorkspaceManager(persistence: nil, initialState: state)
        manager.switchTo(projectID: second.id)
        manager.updateProject(id: first.id) { $0.state.layout = .one }
        XCTAssertEqual(manager.workspace.projects[0].state.layout, .one)
        XCTAssertEqual(manager.activeProject, second)
    }

    @MainActor
    func testDuplicateProjectPreservesStateWithIndependentIdentity() {
        var original = Project(name: "Research")
        original.state.layout = .three
        let state = WorkspaceState(favoritesSeeded: true, activeProjectID: original.id, projects: [original])
        let manager = WorkspaceManager(persistence: nil, initialState: state)
        manager.duplicateProject(original.id)
        XCTAssertNotEqual(manager.activeProject.id, original.id)
        XCTAssertEqual(manager.activeProject.state, original.state)
        XCTAssertEqual(manager.activeProject.name, "Research Copy")
        manager.duplicateProject(original.id)
        XCTAssertEqual(manager.activeProject.name, "Research Copy 2")
        manager.updateProject(id: manager.activeProject.id) { $0.state.layout = .one }
        XCTAssertEqual(manager.workspace.projects.first?.state.layout, .three)
    }

    @MainActor
    func testQuitFlushIncludesMutationWhoseDebounceHasNotFired() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try PersistenceService(stateURL: root.appendingPathComponent("state.json"))
        var state = WorkspaceState.empty
        state.favoritesSeeded = true
        let manager = WorkspaceManager(persistence: service, initialState: state)
        manager.setColorScheme(.dark)
        manager.saveSynchronously()
        XCTAssertEqual(service.loadState()?.settings.colorScheme, .dark)
    }
}
