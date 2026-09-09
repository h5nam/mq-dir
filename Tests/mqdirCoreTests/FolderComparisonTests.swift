import XCTest
@testable import mqdirCore

final class FolderComparisonTests: XCTestCase {
    func testReportsSidesAndMetadataWithoutClaimingContentEquality() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let left = root.appendingPathComponent("left"), right = root.appendingPathComponent("right")
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: left.appendingPathComponent("only-left"))
        try Data("b".utf8).write(to: right.appendingPathComponent("only-right"))
        for directory in [left, right] {
            try Data("same".utf8).write(to: directory.appendingPathComponent("same"))
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: directory.appendingPathComponent("same").path)
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("folder"), withIntermediateDirectories: false)
        }
        let rows = try FolderComparison.compare(left: left, right: right, cancellation: .init())
        XCTAssertEqual(rows.first { $0.name == "only-left" }?.status, .leftOnly)
        XCTAssertEqual(rows.first { $0.name == "only-right" }?.status, .rightOnly)
        XCTAssertEqual(rows.first { $0.name == "same" }?.status, .same)
        XCTAssertEqual(rows.first { $0.name == "folder" }?.status, .folder)
    }
    func testScrollAnchorFieldsDefaultAndRoundTrip() throws {
        let tab = TabState(listScrollPath: "/fixture/file", treeScrollPath: "/fixture/deep/file")
        XCTAssertEqual(try JSONDecoder().decode(TabState.self, from: JSONEncoder().encode(tab)), tab)
        let legacy = try JSONDecoder().decode(TabState.self, from: Data("{}".utf8))
        XCTAssertNil(legacy.listScrollPath)
        XCTAssertNil(legacy.treeScrollPath)
    }
}
