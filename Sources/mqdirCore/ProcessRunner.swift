import Darwin
import Foundation

/// Blocking subprocess mechanics for background workers. Both pipes are drained
/// without waiting for child exit; retained output and execution time are bounded.
public enum ProcessRunner {
    public final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        public init() {}
        public func cancel() {
            lock.lock()
            defer { lock.unlock() }
            cancelled = true
        }
        public var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    public enum Failure: Error, Equatable, LocalizedError {
        case cancelled
        case timedOut
        case outputLimitExceeded
        case exited(Int32, String)

        public var errorDescription: String? {
            switch self {
            case .cancelled: return "The operation was cancelled."
            case .timedOut: return "The operation exceeded its time limit."
            case .outputLimitExceeded: return "This item is too large to preview."
            case .exited(let code, let message):
                return message.isEmpty ? "Process exited with status \(code)." : message
            }
        }
    }

    struct Output {
        var stdout = Data()
        var stderr = Data()
    }

    static func run(
        executable: URL,
        arguments: [String],
        directory: URL? = nil,
        timeout: TimeInterval = 3600,
        outputLimit: Int = 64 * 1024,
        stopAtOutputLimit: Bool = false,
        isCancelled: @Sendable () -> Bool = { false },
        environment: [String: String]? = nil
    ) throws -> Output {
        if isCancelled() { throw Failure.cancelled }
        guard timeout.isFinite, timeout > 0 else { throw Failure.timedOut }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        // An encrypted archive must fail instead of waiting for terminal input.
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        defer {
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
        }
        for handle in [stdout.fileHandleForReading, stderr.fileHandleForReading] {
            let fd = handle.fileDescriptor
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        let began = ProcessInfo.processInfo.systemUptime
        try process.run()
        // Parent must not keep the writing ends alive after spawn.
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        var output = Output()
        var outEOF = false
        var errEOF = false
        var outputExceeded = false
        var failure: Failure?
        var stoppingAt: TimeInterval?
        var killed = false
        var bytes = [UInt8](repeating: 0, count: 16 * 1024)
        let limit = max(0, outputLimit)

        func drain(_ fd: Int32, into data: inout Data, eof: inout Bool) {
            // Bound work per turn even when a child writes continuously.
            for _ in 0..<16 where !eof {
                let count = Darwin.read(fd, &bytes, bytes.count)
                if count > 0 {
                    let streamLimit = fd == stdout.fileHandleForReading.fileDescriptor ? limit : min(limit, 64 * 1024)
                    let keep = min(count, max(0, streamLimit - data.count))
                    if keep > 0 { data.append(contentsOf: bytes.prefix(keep)) }
                    if fd == stdout.fileHandleForReading.fileDescriptor, count > keep { outputExceeded = true }
                } else if count == 0 {
                    eof = true
                } else if errno != EINTR {
                    if errno != EAGAIN && errno != EWOULDBLOCK { eof = true }
                    break
                }
            }
        }

        while true {
            drain(stdout.fileHandleForReading.fileDescriptor, into: &output.stdout, eof: &outEOF)
            drain(stderr.fileHandleForReading.fileDescriptor, into: &output.stderr, eof: &errEOF)
            let now = ProcessInfo.processInfo.systemUptime
            if failure == nil {
                if isCancelled() {
                    failure = .cancelled
                } else if outputExceeded && stopAtOutputLimit {
                    failure = .outputLimitExceeded
                } else if now - began >= timeout {
                    failure = .timedOut
                }
                if failure != nil {
                    stoppingAt = now
                    if process.isRunning { process.terminate() }
                }
            }
            if let stoppingAt, now - stoppingAt >= 0.25, process.isRunning, !killed {
                // SIGTERM can be ignored; SIGKILL targets only the owned child.
                kill(process.processIdentifier, SIGKILL)
                killed = true
            }
            if !process.isRunning {
                if outEOF && errEOF { break }
                // A descendant may have inherited a pipe. Never wait forever
                // for it after our child has exited and the deadline elapsed.
                if failure != nil { break }
            }
            usleep(10_000)
        }
        process.waitUntilExit()
        if let failure { throw failure }
        guard process.terminationStatus == 0 else {
            let diagnostic = output.stderr.isEmpty ? output.stdout : output.stderr
            let detail = String(decoding: diagnostic, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.exited(process.terminationStatus, detail)
        }
        return output
    }
}
