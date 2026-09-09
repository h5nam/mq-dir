import XCTest

@testable import mqdirCore

final class ArchiveLifecycleTests: XCTestCase {
    func testFailedExtractionDoesNotLeaveDestinationOrStaging() throws {
        try withFixture { root in
            let archive = root.appendingPathComponent("broken.zip")
            let destination = root.appendingPathComponent("extracted")
            try Data("not an archive".utf8).write(to: archive)
            XCTAssertThrowsError(
                try FileOperationService.runExtraction(kind: .zip, archive: archive, destination: destination))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["broken.zip"])
        }
    }

    func testCompressionRefusesToUpdateExistingArchive() throws {
        try withFixture { root in
            let file = root.appendingPathComponent("item.txt")
            let archive = root.appendingPathComponent("result.zip")
            try Data("original".utf8).write(to: file)
            try FileOperationService.runCompression(parent: root, sources: ["item.txt"], destination: archive)
            let original = try Data(contentsOf: archive)
            try Data("replacement".utf8).write(to: file)
            XCTAssertThrowsError(
                try FileOperationService.runCompression(parent: root, sources: ["item.txt"], destination: archive))
            XCTAssertEqual(try Data(contentsOf: archive), original)
        }
    }

    func testTimeoutCleansStagingAndPreservesSource() throws {
        try withFixture { root in
            let file = root.appendingPathComponent("item.txt")
            try Data("original".utf8).write(to: file)
            XCTAssertThrowsError(
                try FileOperationService.runCompression(
                    parent: root, sources: ["item.txt"], destination: root.appendingPathComponent("out.zip"), timeout: 0
                )
            ) { XCTAssertEqual($0 as? ProcessRunner.Failure, .timedOut) }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["item.txt"])
            XCTAssertEqual(try Data(contentsOf: file), Data("original".utf8))
        }
    }

    func testCancelledExtractionDoesNotCreateDestination() throws {
        try withFixture { root in
            XCTAssertThrowsError(
                try FileOperationService.runExtraction(
                    kind: .zip, archive: root.appendingPathComponent("missing.zip"),
                    destination: root.appendingPathComponent("out"), isCancelled: { true }
                )
            ) { XCTAssertEqual($0 as? ProcessRunner.Failure, .cancelled) }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }

    func testLeadingDashFilenameIsArchivedLiterally() throws {
        try withFixture { root in
            let file = root.appendingPathComponent("-T.txt")
            let archive = root.appendingPathComponent("out.zip")
            let output = root.appendingPathComponent("extracted")
            try Data("literal".utf8).write(to: file)
            try FileOperationService.runCompression(parent: root, sources: ["-T.txt"], destination: archive)
            try FileOperationService.runExtraction(kind: .zip, archive: archive, destination: output)
            XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("-T.txt")), Data("literal".utf8))
        }
    }

    func testTarAndGzipExtractionRoundTrips() throws {
        try withFixture { root in
            try Data("tar payload".utf8).write(to: root.appendingPathComponent("item.txt"))
            for (index, compressed) in [false, true].enumerated() {
                let archive = root.appendingPathComponent("input-\(index).tar")
                _ = try ProcessRunner.run(
                    executable: URL(fileURLWithPath: "/usr/bin/tar"),
                    arguments: [compressed ? "-czf" : "-cf", archive.path, "-C", root.path, "item.txt"])
                let destination = root.appendingPathComponent("result-\(index)")
                try FileOperationService.runExtraction(
                    kind: compressed ? .tarGz : .tar,
                    archive: archive, destination: destination)
                XCTAssertEqual(
                    try Data(contentsOf: destination.appendingPathComponent("item.txt")), Data("tar payload".utf8))
            }
        }
    }

    private func withFixture(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
