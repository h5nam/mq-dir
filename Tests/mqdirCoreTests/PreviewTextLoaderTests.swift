import XCTest

@testable import mqdirCore

final class PreviewTextLoaderTests: XCTestCase {
    func testExactUTF8ByteLimitAndOversize() throws {
        try withFile(Data("한글".utf8)) { url in
            XCTAssertEqual(try PreviewTextLoader.load(at: url, maximumBytes: 6), "한글")
            XCTAssertThrowsError(try PreviewTextLoader.load(at: url, maximumBytes: 5))
        }
    }

    func testInvalidEncodingAndEmptyFile() throws {
        try withFile(Data([0xff])) { url in
            XCTAssertThrowsError(try PreviewTextLoader.load(at: url))
        }
        try withFile(Data()) { url in
            XCTAssertEqual(try PreviewTextLoader.load(at: url, maximumBytes: 0), "")
        }
    }

    func testCancellationBeforeReading() {
        XCTAssertThrowsError(try PreviewTextLoader.load(at: URL(fileURLWithPath: "/missing.md"), isCancelled: { true }))
        {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    func testDirectoryIsRejected() {
        XCTAssertThrowsError(try PreviewTextLoader.load(at: FileManager.default.temporaryDirectory))
    }

    private func withFile(_ data: Data, body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        try body(url)
    }
}
