import XCTest

@testable import mqdirCore

final class FileDropTests: XCTestCase {
    func testSameLocalVolumeMovesUsingActualVolumeMetadata() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let destination = root.appendingPathComponent("destination")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("item.txt")
        try Data("payload".utf8).write(to: source)
        let failures = FileOperationService.transferDroppedItems([source], into: destination, forceCopy: false)
        XCTAssertTrue(failures.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("item.txt")), Data("payload".utf8))
    }

    func testMixedVolumesMoveOnlySameVolumeSource() throws {
        try checkDrop(forceCopy: false, unknownVolumes: false, expectsMove: true)
    }

    func testOptionDropPreservesAllSources() throws {
        try checkDrop(forceCopy: true, unknownVolumes: false, expectsMove: false)
    }

    func testUnknownVolumeDefaultsToCopy() throws {
        try checkDrop(forceCopy: false, unknownVolumes: true, expectsMove: false)
    }

    private func checkDrop(forceCopy: Bool, unknownVolumes: Bool, expectsMove: Bool) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        for name in ["same", "other", "destination"] {
            try fm.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let same = root.appendingPathComponent("same/item.txt")
        let other = root.appendingPathComponent("other/item.txt")
        let destination = root.appendingPathComponent("destination")
        try Data("same volume".utf8).write(to: same)
        try Data("other volume".utf8).write(to: other)
        let failures = FileOperationService.transferDroppedItems(
            [same, other], into: destination, forceCopy: forceCopy,
            volumeIdentifier: { url in
                if unknownVolumes { return nil }
                return url.lastPathComponent == "other" ? 2 : 1
            }
        )
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(fm.fileExists(atPath: same.path), !expectsMove)
        XCTAssertEqual(try String(contentsOf: other, encoding: .utf8), "other volume")
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("item.txt"), encoding: .utf8), "same volume")
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("item 2.txt"), encoding: .utf8), "other volume")
    }
}
