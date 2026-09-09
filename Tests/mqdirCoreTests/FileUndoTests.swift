import XCTest
@testable import mqdirCore

final class FileUndoTests: XCTestCase {
    func testUndoCopyKeepsOriginalAndRemovesUnchangedCopy() throws {
        try withCopy { source, outcome in
            let receipt = try XCTUnwrap(outcome.undoReceipt)
            try receipt.apply(cancellation: .init())
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.current.path))
        }
    }

    func testUndoRejectsChangedCopyAndKeepsIt() throws {
        try withCopy { _, outcome in
            let receipt = try XCTUnwrap(outcome.undoReceipt)
            try Data("external edit".utf8).write(to: receipt.current)
            XCTAssertThrowsError(try receipt.apply(cancellation: .init()))
            XCTAssertEqual(try Data(contentsOf: receipt.current), Data("external edit".utf8))
        }
    }

    func testUndoCopyRejectsMissingOriginal() throws {
        try withCopy { source, outcome in
            let receipt = try XCTUnwrap(outcome.undoReceipt)
            try FileManager.default.removeItem(at: source)
            XCTAssertThrowsError(try receipt.apply(cancellation: .init()))
            XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.current.path))
        }
    }

    func testDirectoryMoveUndoRejectsNestedChanges() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: source.appendingPathComponent("file.txt"))
        let result = FileOperationService.perform(FileWorkRequest(kind: .move, sources: [source], destination: destination), sources: [source], cancellation: .init())
        let receipt = try XCTUnwrap(result.undoReceipt)
        try Data("external".utf8).write(to: receipt.current.appendingPathComponent("file.txt"))
        XCTAssertThrowsError(try receipt.apply(cancellation: .init()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testRenameUndoRefusesOccupiedOriginalPath() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: source)
        let result = FileOperationService.perform(FileWorkRequest(kind: .rename, sources: [source], newName: "renamed.txt"), sources: [source], cancellation: .init())
        let receipt = try XCTUnwrap(result.undoReceipt)
        try Data("another file".utf8).write(to: source)
        XCTAssertThrowsError(try receipt.apply(cancellation: .init()))
        XCTAssertEqual(try Data(contentsOf: source), Data("another file".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.current.path))
    }

    private func withCopy(_ body: (URL, FileWorkOutcome) throws -> Void) throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("file.txt")
        try Data("original".utf8).write(to: source)
        let result = FileOperationService.perform(FileWorkRequest(kind: .copy, sources: [source], destination: root), sources: [source], cancellation: .init())
        XCTAssertEqual(result.status, .succeeded)
        try body(source, result)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
