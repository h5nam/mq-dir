import CryptoKit
import Foundation

/// Captures content and identity, including descendants, without following
/// symlinks found inside a directory. A failed capture simply disables Undo.
struct FileFingerprint: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let relativePath: String
        let content: String
        let inode: UInt64
        let device: UInt64
        let size: UInt64
        let modified: Date?
        let permissions: UInt16
    }
    let entries: [Entry]
    var content: [String] { entries.map { $0.relativePath + "\0" + $0.content } }

    static func capture(_ root: URL, cancellation: ProcessRunner.Cancellation = .init()) throws -> Self {
        let fm = FileManager.default
        var urls: [(URL, String)] = [(root, "")]
        let rootAttributes = try fm.attributesOfItem(atPath: root.path)
        if rootAttributes[.type] as? FileAttributeType == .typeDirectory {
            var enumerationError: Error?
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: { _, error in
                enumerationError = error
                return false
            }) else { throw CocoaError(.fileReadUnknown) }
            for case let url as URL in enumerator {
                if cancellation.isCancelled { throw CancellationError() }
                urls.append((url, url.pathComponents.suffix(enumerator.level).joined(separator: "/")))
            }
            if let enumerationError { throw enumerationError }
        }
        var entries: [Entry] = []
        for (url, relative) in urls.sorted(by: { $0.1 < $1.1 }) {
            if cancellation.isCancelled { throw CancellationError() }
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let type = attributes[.type] as? FileAttributeType
            var hash = SHA256()
            if type == .typeRegular {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty {
                    if cancellation.isCancelled { throw CancellationError() }
                    hash.update(data: data)
                }
            } else if type == .typeSymbolicLink {
                hash.update(data: Data(try fm.destinationOfSymbolicLink(atPath: url.path).utf8))
            } else if type != .typeDirectory {
                throw CocoaError(.fileReadUnknown)
            }
            let tags = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
            let content = (type?.rawValue ?? "") + ":" + Data(hash.finalize()).base64EncodedString()
                + ":" + tags.sorted().joined(separator: "\0")
            entries.append(Entry(relativePath: relative, content: content,
                inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                device: (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
                size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                modified: attributes[.modificationDate] as? Date,
                permissions: (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0))
        }
        return FileFingerprint(entries: entries)
    }
}

struct FileUndoReceipt: Sendable, Equatable, Identifiable {
    enum Kind: Sendable { case removeCopy, moveBack }
    let id = UUID()
    let kind: Kind
    let original: URL
    let current: URL
    let expectedCurrent: FileFingerprint
    let expectedOriginal: FileFingerprint?

    enum Failure: Error, LocalizedError {
        case changed, occupied
        var errorDescription: String? {
            switch self {
            case .changed: "The files changed after this operation. Undo was stopped to preserve those changes."
            case .occupied: "The original location is occupied. Undo will not overwrite it."
            }
        }
    }

    func apply(cancellation: ProcessRunner.Cancellation) throws {
        guard try FileFingerprint.capture(current, cancellation: cancellation) == expectedCurrent else { throw Failure.changed }
        if cancellation.isCancelled { throw CancellationError() }
        switch kind {
        case .removeCopy:
            // Keep the copy if the original was removed or modified meanwhile.
            guard let expectedOriginal,
                  try FileFingerprint.capture(original, cancellation: cancellation) == expectedOriginal else { throw Failure.changed }
            try FileManager.default.removeItem(at: current)
        case .moveBack:
            guard !FileManager.default.fileExists(atPath: original.path) else { throw Failure.occupied }
            try FileManager.default.moveItem(at: current, to: original)
        }
    }
}
