import XCTest
@testable import mqdirCore

final class FileWorkTests: XCTestCase {
    func testCopyInPlaceReportsActualRenamedDestination() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("file.txt")
        try Data("original".utf8).write(to: source)
        let result = FileOperationService.perform(FileWorkRequest(kind: .copy, sources: [source], destination: root),
            sources: [source], cancellation: .init())
        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.destination?.lastPathComponent, "file 2.txt")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(result.destination)), Data("original".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testSkippedAndFailedAreNotReportedAsSuccessful() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder")
        let child = folder.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let skipped = FileOperationService.transferOutcome(folder, into: child, move: true)
        guard case .skipped = skipped.status else { return XCTFail("Expected explicit skipped result") }
        let missing = root.appendingPathComponent("missing")
        let failed = FileOperationService.transferOutcome(missing, into: folder, move: false)
        XCTAssertTrue(failed.needsRetry)
        XCTAssertNotEqual(failed.status, .succeeded)
    }

    func testChangeScopeExcludesUnrelatedFolders() {
        let root = URL(fileURLWithPath: "/fixture/project")
        XCTAssertFalse(FileChangeScope.affects(root: root, changedFolders: [URL(fileURLWithPath: "/fixture/other")], recursive: true))
        XCTAssertFalse(FileChangeScope.affects(root: root, changedFolders: [URL(fileURLWithPath: "/fixture/project/deep/nested")], recursive: false))
        XCTAssertTrue(FileChangeScope.affects(root: root, changedFolders: [URL(fileURLWithPath: "/fixture/project/deep/nested")], recursive: true))
        XCTAssertTrue(FileChangeScope.affects(root: root, changedFolders: nil, recursive: false))
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
