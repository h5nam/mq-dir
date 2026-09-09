import XCTest

@testable import mqdirCore

final class RenameBoundaryTests: XCTestCase {
    func testRenameRejectsPathComponentsWithoutMovingSource() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let parent = root.appendingPathComponent("parent")
        try fm.createDirectory(at: parent, withIntermediateDirectories: false)
        for name in ["../escaped.txt", "child/file.txt", "/absolute.txt", ".", "..", "", "bad\0name"] {
            let source = parent.appendingPathComponent("original.txt")
            try Data("original".utf8).write(to: source)
            XCTAssertThrowsError(try FileOperationService.rename(source, to: name), name)
            XCTAssertEqual(try? String(contentsOf: source, encoding: .utf8), "original", name)
            XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("escaped.txt").path))
        }
    }

    func testRenameAcceptsUnicodeAndLiteralPercentEncoding() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: source)
        let target = try FileOperationService.rename(source, to: "한글 %2F.txt")
        XCTAssertEqual(target.deletingLastPathComponent().path, root.path)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "original")
    }
}
