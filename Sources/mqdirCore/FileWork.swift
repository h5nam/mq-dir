import Foundation

enum FileWorkKind: String, Sendable, CaseIterable {
    case copy, move, drop, duplicate, trash, delete, compress, extract, rename, undo

    var title: String {
        switch self {
        case .copy: "Copy"
        case .move: "Move"
        case .drop: "Transfer"
        case .duplicate: "Duplicate"
        case .trash: "Move to Trash"
        case .delete: "Delete permanently"
        case .compress: "Compress"
        case .extract: "Extract"
        case .rename: "Rename"
        case .undo: "Undo"
        }
    }
}

struct FileWorkRequest: Sendable, Equatable {
    let kind: FileWorkKind
    var sources: [URL]
    var destination: URL? = nil
    var forceCopy = false
    var normalizeHangul = false
    var newName: String? = nil
    var undoReceipts: [FileUndoReceipt] = []

    var unitCount: Int { kind == .compress ? 1 : sources.count }
    var units: [[URL]] { kind == .compress ? [sources] : sources.map { [$0] } }
}

struct FileWorkOutcome: Sendable, Identifiable {
    enum Status: Sendable, Equatable {
        case succeeded
        case skipped(String)
        case failed(String)
        case cancelled
    }
    let id = UUID()
    let sources: [URL]
    let destination: URL?
    let status: Status
    var undoReceipt: FileUndoReceipt? = nil

    var needsRetry: Bool {
        switch status {
        case .failed, .cancelled: true
        case .succeeded, .skipped: false
        }
    }
}

extension FileOperationService {
    /// One result per submitted unit, including skipped and cancelled work.
    static func perform(_ request: FileWorkRequest, sources: [URL], cancellation: ProcessRunner.Cancellation) -> FileWorkOutcome {
        guard !cancellation.isCancelled else {
            return FileWorkOutcome(sources: sources, destination: nil, status: .cancelled)
        }
        var destination: URL?
        var receipt: FileUndoReceipt?
        do {
            guard let source = sources.first else { throw CocoaError(.fileReadInvalidFileName) }
            switch request.kind {
            case .copy, .move, .drop, .duplicate:
                let folder = request.kind == .duplicate ? source.deletingLastPathComponent() : request.destination
                guard let folder else { throw CocoaError(.fileWriteInvalidFileName) }
                var move = request.kind == .move
                if request.kind == .drop {
                    let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
                    let a = (try? source.deletingLastPathComponent().resourceValues(forKeys: keys))?.volumeIdentifier as? AnyHashable
                    let b = (try? folder.resourceValues(forKeys: keys))?.volumeIdentifier as? AnyHashable
                    move = !request.forceCopy && a != nil && a == b
                }
                return transferOutcome(source, into: folder, move: move,
                    duplicateInPlace: request.kind == .copy || request.kind == .duplicate,
                    normalizeHangul: request.normalizeHangul, recordUndo: true, cancellation: cancellation)
            case .trash:
                let before = try? FileFingerprint.capture(source, cancellation: cancellation)
                var trashed: NSURL?
                try FileManager.default.trashItem(at: source, resultingItemURL: &trashed)
                destination = trashed as URL?
                if let before, let destination,
                   let after = try? FileFingerprint.capture(destination, cancellation: cancellation), before.content == after.content {
                    receipt = FileUndoReceipt(kind: .moveBack, original: source, current: destination,
                        expectedCurrent: after, expectedOriginal: nil)
                }
            case .rename:
                guard let name = request.newName else { throw RenameError.invalidName }
                let before = try? FileFingerprint.capture(source, cancellation: cancellation)
                destination = try rename(source, to: name)
                if let before, let destination,
                   let after = try? FileFingerprint.capture(destination, cancellation: cancellation), before.content == after.content {
                    receipt = FileUndoReceipt(kind: .moveBack, original: source, current: destination,
                        expectedCurrent: after, expectedOriginal: nil)
                }
            case .undo:
                guard let undo = request.undoReceipts.first(where: { $0.current == source }) else { throw FileUndoReceipt.Failure.changed }
                try undo.apply(cancellation: cancellation)
                destination = undo.original
            case .delete:
                try FileManager.default.removeItem(at: source)
            case .compress:
                let items = try sources.map { url in
                    (url: url, isDirectory: try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false)
                }
                guard let plan = try planCompression(urls: items) else { throw CocoaError(.fileReadInvalidFileName) }
                destination = plan.destination
                try runCompression(parent: plan.parent, sources: plan.sourceNames, destination: plan.destination,
                    isCancelled: { cancellation.isCancelled })
            case .extract:
                guard let kind = archiveKind(for: source) else { throw CocoaError(.fileReadUnknown) }
                destination = try extract(archive: source, kind: kind, isCancelled: { cancellation.isCancelled })
            }
            return FileWorkOutcome(sources: sources, destination: destination, status: .succeeded, undoReceipt: receipt)
        } catch is CancellationError {
            return FileWorkOutcome(sources: sources, destination: destination, status: .cancelled)
        } catch ProcessRunner.Failure.cancelled {
            return FileWorkOutcome(sources: sources, destination: destination, status: .cancelled)
        } catch {
            return FileWorkOutcome(sources: sources, destination: destination, status: .failed(error.localizedDescription))
        }
    }

    static func transferOutcome(
        _ source: URL, into folder: URL, move: Bool, duplicateInPlace: Bool = false,
        normalizeHangul: Bool = false, fileManager: FileManager = .default, recordUndo: Bool = false, cancellation: ProcessRunner.Cancellation = .init()
    ) -> FileWorkOutcome {
        var target = folder.appendingPathComponent(source.lastPathComponent)
        if source.standardizedFileURL == target.standardizedFileURL && !duplicateInPlace {
            return FileWorkOutcome(sources: [source], destination: source, status: .skipped("Already in this folder"))
        }
        let sourceParts = source.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let folderParts = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        if folderParts.starts(with: sourceParts) {
            return FileWorkOutcome(sources: [source], destination: nil, status: .skipped("A folder cannot be placed inside itself"))
        }
        if fileManager.fileExists(atPath: target.path) {
            target = conflictRenamedDestination(for: source, in: folder,
                fileExists: { fileManager.fileExists(atPath: $0) })
        }
        let original = recordUndo ? try? FileFingerprint.capture(source, cancellation: cancellation) : nil
        if cancellation.isCancelled { return FileWorkOutcome(sources: [source], destination: target, status: .cancelled) }
        do {
            if move { try fileManager.moveItem(at: source, to: target) }
            else { try fileManager.copyItem(at: source, to: target) }
            if normalizeHangul, let normalized = HangulNFCFilename.renameToNFC(target) { target = normalized }
            var receipt: FileUndoReceipt?
            if let original, let current = try? FileFingerprint.capture(target, cancellation: cancellation), original.content == current.content {
                receipt = FileUndoReceipt(kind: move ? .moveBack : .removeCopy, original: source, current: target,
                    expectedCurrent: current, expectedOriginal: move ? nil : original)
            }
            return FileWorkOutcome(sources: [source], destination: target, status: .succeeded, undoReceipt: receipt)
        } catch {
            return FileWorkOutcome(sources: [source], destination: target, status: .failed(error.localizedDescription))
        }
    }
}
