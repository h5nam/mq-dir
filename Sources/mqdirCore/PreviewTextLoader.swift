import Foundation

/// Bounded file I/O for the Markdown preview's background worker.
enum PreviewTextLoader {
    enum Failure: Error, LocalizedError {
        case tooLarge
        case unsupportedFile
        case invalidEncoding

        var errorDescription: String? {
            switch self {
            case .tooLarge: return "This document is too large for the in-pane preview."
            case .unsupportedFile: return "This item is not a regular text file."
            case .invalidEncoding: return "This document is not UTF-8 text."
            }
        }
    }

    static func load(
        at url: URL, maximumBytes: Int = 2_000_000,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> String {
        let data = try readData(at: url, maximumBytes: maximumBytes, isCancelled: isCancelled)
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.invalidEncoding }
        return text
    }

    static func readData(at url: URL, maximumBytes: Int, isCancelled: @Sendable () -> Bool = { false }) throws -> Data {
        if isCancelled() { throw CancellationError() }
        guard maximumBytes >= 0, maximumBytes < Int.max else { throw Failure.tooLarge }
        let resolved = url.resolvingSymlinksInPath()
        let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw Failure.unsupportedFile }
        if let size = values.fileSize, size > maximumBytes { throw Failure.tooLarge }
        let handle = try FileHandle(forReadingFrom: resolved)
        defer { try? handle.close() }
        var data = Data()
        // Enforce the bound during reading too: files may grow after stat.
        while data.count <= maximumBytes {
            if isCancelled() { throw CancellationError() }
            let chunk = try handle.read(upToCount: min(64 * 1024, maximumBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        return data
    }

}
