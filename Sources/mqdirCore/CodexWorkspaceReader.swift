import Darwin
import Foundation

/// Read-only JSON-lines client. It never starts/resumes a thread or sends a turn.
enum CodexWorkspaceReader {
    static func read(
        executable: URL, environment: [String: String], cancellation: ProcessRunner.Cancellation,
        timeout: TimeInterval = 12
    ) throws -> [IntegrationWorkspace] {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        var didLaunch = false
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        for handle in [output.fileHandleForReading, errors.fileHandleForReading] {
            let fd = handle.fileDescriptor
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) >= 0 else {
                throw WorkspaceMetadata.Failure.malformed
            }
        }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                let end = ProcessInfo.processInfo.systemUptime + 0.25
                while process.isRunning, ProcessInfo.processInfo.systemUptime < end { usleep(10_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            if didLaunch { process.waitUntilExit() }
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
        }
        if cancellation.isCancelled { throw ProcessRunner.Failure.cancelled }
        try process.run()
        didLaunch = true
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        func send(_ message: [String: Any]) throws {
            var bytes = try JSONSerialization.data(withJSONObject: message)
            bytes.append(10)
            try input.fileHandleForWriting.write(contentsOf: bytes)
        }
        try send([
            "id": 0, "method": "initialize",
            "params": ["clientInfo": ["name": "mqdir_workspace_reader", "title": "mq-dir", "version": "0.2.0"]],
        ])
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        var requestID = 0
        var workspaces: [IntegrationWorkspace] = []
        var seenCursors = Set<String>()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            if cancellation.isCancelled { throw ProcessRunner.Failure.cancelled }
            let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &chunk, chunk.count)
            if count > 0 { buffer.append(contentsOf: chunk.prefix(count)) }
            _ = Darwin.read(errors.fileHandleForReading.fileDescriptor, &chunk, chunk.count)
            guard buffer.count <= 8 * 1024 * 1024 else { throw ProcessRunner.Failure.outputLimitExceeded }
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                    message["id"] as? Int == requestID
                else { continue }
                guard let result = message["result"] as? [String: Any] else {
                    throw WorkspaceMetadata.Failure.malformed
                }
                var cursor: String?
                if requestID == 0 {
                    try send(["method": "initialized", "params": [:]])
                } else {
                    guard let rows = result["data"] as? [[String: Any]] else {
                        throw WorkspaceMetadata.Failure.malformed
                    }
                    workspaces.append(contentsOf: WorkspaceMetadata.codex(rows))
                    cursor = result["nextCursor"] as? String
                    if cursor == nil { return workspaces }
                    if requestID >= 20 { return workspaces }
                    guard let cursor, seenCursors.insert(cursor).inserted else {
                        throw WorkspaceMetadata.Failure.malformed
                    }
                }
                requestID += 1
                var params: [String: Any] = [
                    "limit": 100, "archived": false, "useStateDbOnly": true,
                    "sourceKinds": ["cli", "vscode", "appServer"], "sortKey": "updated_at",
                ]
                if let cursor { params["cursor"] = cursor }
                try send(["id": requestID, "method": "thread/list", "params": params])
            }
            if count <= 0 { usleep(10_000) }
        }
        throw ProcessRunner.Failure.timedOut
    }
}
