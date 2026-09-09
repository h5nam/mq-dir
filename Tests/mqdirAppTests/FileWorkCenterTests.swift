import XCTest

final class FileWorkCenterTests: XCTestCase {
    @MainActor
    func testRetryOnlyProcessesFailedSources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let good = root.appendingPathComponent("good.txt")
        let missing = root.appendingPathComponent("missing.txt")
        try Data("good".utf8).write(to: good)
        let center = FileWorkCenter()
        let job = try XCTUnwrap(center.submit(FileWorkRequest(kind: .copy, sources: [good, missing], destination: destination)))
        try await wait { !job.isActive }
        XCTAssertEqual(job.successCount, 1)
        XCTAssertEqual(job.failedCount, 1)
        try Data("fixed".utf8).write(to: missing)
        center.retry(job)
        let retry = try XCTUnwrap(center.jobs.last)
        try await wait { !retry.isActive }
        XCTAssertEqual(retry.request.sources, [missing])
        XCTAssertEqual(retry.successCount, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted(), ["good.txt", "missing.txt"])
    }

    @MainActor
    func testDuplicateRequestIsSuppressedAndQueuedCancellationDoesNoWork() async throws {
        let center = FileWorkCenter { _, sources, _ in
            XCTFail("Cancelled queued work must not execute")
            return FileWorkOutcome(sources: sources, destination: nil, status: .succeeded)
        }
        let request = FileWorkRequest(kind: .copy, sources: [URL(fileURLWithPath: "/fixture/a")])
        let job = try XCTUnwrap(center.submit(request))
        XCTAssertTrue(center.submit(request) === job)
        XCTAssertEqual(center.jobs.count, 1)
        center.cancel(job)
        try await wait { !job.isActive }
        XCTAssertEqual(job.cancelledCount, 1)
        XCTAssertEqual(job.successCount, 0)
    }

    @MainActor
    func testCancelDuringAnItemPreservesItsSuccessAndStopsRemainingItems() async throws {
        let started = expectation(description: "first item started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let center = FileWorkCenter { _, sources, _ in
            started.fulfill()
            _ = release.wait(timeout: .now() + 3)
            return FileWorkOutcome(sources: sources, destination: nil, status: .succeeded)
        }
        let job = try XCTUnwrap(center.submit(FileWorkRequest(kind: .copy,
            sources: ["a", "b", "c"].map { URL(fileURLWithPath: "/fixture/" + $0) })))
        await fulfillment(of: [started], timeout: 2)
        center.cancel(job)
        release.signal()
        try await wait { !job.isActive }
        XCTAssertEqual(job.successCount, 1)
        XCTAssertEqual(job.cancelledCount, 2)
        XCTAssertEqual(job.processedCount, 3)
    }

    @MainActor
    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(predicate())
    }
}
