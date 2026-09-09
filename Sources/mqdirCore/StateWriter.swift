import Foundation

/// FIFO writes and the termination flush share one queue. Enqueue from the
/// workspace's main-actor owner; never wait for the main actor inside a write.
final class StateWriter: Sendable {
    private let queue = DispatchQueue(label: "mqdir.state-writer")
    private let write: @Sendable (WorkspaceState) throws -> Void

    init(write: @escaping @Sendable (WorkspaceState) throws -> Void) {
        self.write = write
    }

    func enqueue(_ state: WorkspaceState) {
        queue.async { [write] in
            do { try write(state) } catch { Self.log(error) }
        }
    }

    func flush(_ state: WorkspaceState) throws {
        try queue.sync { try write(state) }
    }

    static func log(_ error: Error) {
        FileHandle.standardError.write(Data("[mq-dir persist] save failed: \(error.localizedDescription)\n".utf8))
    }
}
