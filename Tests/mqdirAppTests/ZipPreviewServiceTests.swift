import XCTest

final class ZipPreviewServiceTests: XCTestCase {
    func testLiteralPatternsDoNotExtractNeighboringEntries() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("fixture.zip")
        for name in ["report[1]*?.txt", "report111.txt", "-T.txt", "back\\slash.txt"] {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }
        _ = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-j", "-q", archive.path]
                + ["report[1]*?.txt", "report111.txt", "-T.txt", "back\\slash.txt"].map {
                    root.appendingPathComponent($0).path
                })
        let entries = try await ZipPreviewService.list(archive: archive)
        XCTAssertEqual(entries.count, 4)
        for name in ["report[1]*?.txt", "-T.txt", "back\\slash.txt"] {
            let result = try await ZipPreviewService.extract(archive: archive, entry: name)
            XCTAssertEqual(String(decoding: result.data, as: UTF8.self), name)
            XCTAssertFalse(result.truncated)
        }
    }

    func testCancelledRequestDoesNotLaunchExtraction() async {
        let task = Task {
            try await ZipPreviewService.extract(archive: URL(fileURLWithPath: "/missing.zip"), entry: "missing")
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled request should not produce preview data")
        } catch {
            XCTAssertTrue(error is CancellationError || (error as? ProcessRunner.Failure) == .cancelled)
        }
    }

    func testOversizedEntryFailsInsteadOfContinuingToDecode() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("big.txt")
        let archive = root.appendingPathComponent("fixture.zip")
        try Data(repeating: 65, count: ZipPreviewService.extractCap + 1).write(to: source)
        _ = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-j", "-q", archive.path, source.path])
        do {
            _ = try await ZipPreviewService.extract(archive: archive, entry: "big.txt")
            XCTFail("Oversized extraction should stop at its byte limit")
        } catch {
            XCTAssertEqual(error as? ProcessRunner.Failure, .outputLimitExceeded)
        }
    }

    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
