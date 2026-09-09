import XCTest

@testable import mqdirCore

final class ProcessRunnerTests: XCTestCase {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    func testDrainsBothPipesBeyondCapacityWithBoundedCapture() throws {
        let output = try ProcessRunner.run(
            executable: shell,
            arguments: [
                "-c",
                "i=0; while [ $i -lt 12000 ]; do printf 'stdout line 1234567890\\n'; printf 'stderr line 1234567890\\n' >&2; i=$((i+1)); done",
            ], timeout: 10, outputLimit: 1024)
        XCTAssertEqual(output.stdout.count, 1024)
        XCTAssertEqual(output.stderr.count, 1024)
    }

    func testTimeoutKillsChildThatIgnoresTermination() {
        let start = Date()
        XCTAssertThrowsError(
            try ProcessRunner.run(
                executable: shell,
                arguments: ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.1)
        ) {
            XCTAssertEqual($0 as? ProcessRunner.Failure, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testCancellationBeforeLaunchDoesNotExecuteCommand() {
        let token = ProcessRunner.Cancellation()
        token.cancel()
        XCTAssertThrowsError(
            try ProcessRunner.run(
                executable: URL(fileURLWithPath: "/not-an-executable"),
                arguments: [], isCancelled: { token.isCancelled })
        ) {
            XCTAssertEqual($0 as? ProcessRunner.Failure, .cancelled)
        }
    }

    func testCancellationDuringExecutionTerminatesChild() {
        let token = ProcessRunner.Cancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { token.cancel() }
        XCTAssertThrowsError(
            try ProcessRunner.run(
                executable: shell,
                arguments: ["-c", "while :; do :; done"], timeout: 5, isCancelled: { token.isCancelled })
        ) {
            XCTAssertEqual($0 as? ProcessRunner.Failure, .cancelled)
        }
    }

    func testNonzeroExitReportsCapturedStderr() {
        XCTAssertThrowsError(
            try ProcessRunner.run(
                executable: shell,
                arguments: ["-c", "printf 'fixture failure' >&2; exit 7"])
        ) {
            XCTAssertEqual($0 as? ProcessRunner.Failure, .exited(7, "fixture failure"))
        }
    }

    func testStdinIsClosedAndEmptyOutputSucceeds() throws {
        let output = try ProcessRunner.run(
            executable: shell,
            arguments: ["-c", "if read line; then exit 9; fi"], timeout: 2)
        XCTAssertTrue(output.stdout.isEmpty)
    }
}
