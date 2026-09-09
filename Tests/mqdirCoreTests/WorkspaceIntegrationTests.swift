import XCTest

@testable import mqdirCore

final class WorkspaceIntegrationTests: XCTestCase {
    func testOrcaOnlyIncludesLocalUnarchivedPaths() throws {
        let data = Data(
            #"{"ok":true,"result":{"worktrees":[{"worktreeId":"a","hostId":"local","path":"/fixture/a","displayName":"A","isActive":true},{"worktreeId":"b","hostId":"remote","path":"/fixture/b"},{"worktreeId":"c","hostId":"local","path":"/fixture/c","isArchived":true}]}}"#
                .utf8)
        let result = try WorkspaceMetadata.orca(data)
        XCTAssertEqual(result.map(\.currentDirectory), ["/fixture/a"])
        XCTAssertTrue(result[0].selected)
    }
    func testPaseoUsesDocumentedWorkspaceRows() throws {
        let data = Data(
            #"[{"workspaceId":"ws1","project":"App","name":"feature","isolation":"worktree","cwd":"/fixture/worktree"}]"#
                .utf8)
        XCTAssertEqual(try WorkspaceMetadata.paseo(data).first?.currentDirectory, "/fixture/worktree")
        XCTAssertThrowsError(try WorkspaceMetadata.paseo(Data(#"{"error":"offline"}"#.utf8)))
    }
    func testClaudeDesktopReadsOnlyMetadataFields() throws {
        let data = Data(
            #"{"sessionId":"local_1","cwd":"/fixture/claude","title":"Project","completedTurns":[{"text":"private transcript"}],"remoteMcpServersConfig":{"secret":"not displayed"}}"#
                .utf8)
        let result = try XCTUnwrap(WorkspaceMetadata.claudeDesktop(data))
        XCTAssertEqual(result.title, "Project")
        XCTAssertEqual(result.currentDirectory, "/fixture/claude")
        XCTAssertFalse(String(describing: result).contains("private transcript"))
    }
    func testInvalidPathsAndArchivedSessionsAreExcluded() throws {
        XCTAssertNil(WorkspaceMetadata.validPath("https://example.test/project"))
        XCTAssertNil(WorkspaceMetadata.validPath("/tmp/a\0b"))
        XCTAssertNil(
            try WorkspaceMetadata.claudeDesktop(Data(#"{"sessionId":"a","cwd":"/fixture/a","isArchived":true}"#.utf8)))
    }
    func testProviderChoiceSurvivesSettingsRoundTripAndOldStateDefaults() throws {
        let settings = WorkspaceSettings(integrationProvider: .orca)
        XCTAssertEqual(
            try JSONDecoder().decode(WorkspaceSettings.self, from: JSONEncoder().encode(settings)).integrationProvider,
            .orca)
        XCTAssertEqual(
            try JSONDecoder().decode(WorkspaceSettings.self, from: Data("{}".utf8)).integrationProvider, .cmux)
        XCTAssertEqual(WorkspaceProvider.allCases.count, 5)
    }
    func testCodexEarlyExitIsAnErrorRatherThanSIGPIPE() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("closed-server")
        try Data("#!/bin/sh\nexec 0<&-\nexit 1\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        XCTAssertThrowsError(
            try CodexWorkspaceReader.read(
                executable: script,
                environment: ProcessInfo.processInfo.environment, cancellation: .init(), timeout: 1))
    }

    func testCodexReaderOnlyListsMetadataAndPaginates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("fake-codex")
        let program = #"""
            #!/usr/bin/env python3
            import sys, json
            for line in sys.stdin:
                m=json.loads(line)
                assert m['method'] in ['initialize','initialized','thread/list']
                if m['method']=='initialized': continue
                if m['method']=='initialize': result={}
                else:
                    assert m['params']['useStateDbOnly'] is True
                    page=2 if m['params'].get('cursor') else 1
                    result={'data':[{'id':str(page),'cwd':'/fixture/'+str(page),'name':'Project'}], 'nextCursor':'next' if page==1 else None}
                print(json.dumps({'id':m['id'],'result':result}),flush=True)
            """#
        try Data(program.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let result = try CodexWorkspaceReader.read(
            executable: script, environment: ProcessInfo.processInfo.environment,
            cancellation: .init(), timeout: 3)
        XCTAssertEqual(result.map(\.currentDirectory), ["/fixture/1", "/fixture/2"])
    }
}
