import XCTest

@testable import mqdirCore

final class TraversalCancellationTests: XCTestCase {
    func testAlreadyCancelledSmallTreeDoesNotReturnResultsOrSize() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("payload".utf8).write(to: root.appendingPathComponent("target.txt"))
        let service = FileSystemService()
        XCTAssertTrue(try service.enumerateMatching(root: root, query: "target", isCancelled: { true }).isEmpty)
        XCTAssertEqual(service.directorySize(at: root, isCancelled: { true }), 0)
        XCTAssertThrowsError(try service.enumerateDirectory(at: root, isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    func testDirectoryEntriesPreserveRequestedRootNamespace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("child.txt"))
        let entry = try XCTUnwrap(FileSystemService().enumerateDirectory(at: root).first)
        XCTAssertEqual(entry.url.deletingLastPathComponent().path, root.path)
    }

    func testListingAndRecursiveSearchUseSameIdentityForNestedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let parent = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: parent.appendingPathComponent("한글 #?.txt"))
        let service = FileSystemService()
        let listed = try XCTUnwrap(service.enumerateDirectory(at: parent).first)
        let found = try XCTUnwrap(service.enumerateMatching(root: root, query: ".txt").first)
        XCTAssertEqual(listed.id, found.id)
        XCTAssertEqual(Array(listed.url.lastPathComponent.utf8), Array(listed.name.utf8))
        XCTAssertEqual(found.url.deletingLastPathComponent().path, parent.path)
    }

    func testSearchThroughSymlinkRootKeepsNestedRelativePath() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let actual = base.appendingPathComponent("storage/deep/actual")
        let sub = actual.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data().write(to: sub.appendingPathComponent("target.txt"))
        let alias = base.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual)
        let result = try XCTUnwrap(FileSystemService().enumerateMatching(root: alias, query: "target").first)
        XCTAssertEqual(result.url.path, alias.appendingPathComponent("sub/target.txt").path)
    }

    func testFirstSearchMatchCanBeConsumedBeforeTraversalCompletes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<50 { try Data().write(to: root.appendingPathComponent("target-\(index).txt")) }
        let token = ProcessRunner.Cancellation()
        let result = try FileSystemService().enumerateMatching(root: root, query: "target",
            isCancelled: { token.isCancelled }, onProgress: { partial in
                XCTAssertEqual(partial.count, 1)
                token.cancel()
            })
        XCTAssertEqual(result.count, 1)
    }

    func testOutputLimitStopsContinuouslyWritingChild() {
        let started = Date()
        XCTAssertThrowsError(
            try ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "while :; do printf '012345678901234567890123456789\\n'; done"],
                timeout: 10, outputLimit: 128, stopAtOutputLimit: true)
        ) {
            XCTAssertEqual($0 as? ProcessRunner.Failure, .outputLimitExceeded)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testExactOutputLimitStillSucceeds() throws {
        let result = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["1234"], outputLimit: 4, stopAtOutputLimit: true)
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "1234")
    }
}
