import Foundation

// MARK: - Listing & extraction

/// One row in a `.zip` archive's table of contents — what `unzip -Z -1`
/// emits, one path per line. Directories carry a trailing `/`; everything
/// else is a file. We don't store sizes here because `-Z -1` doesn't
/// emit them; the header line under `ZipPreviewView` covers the
/// archive-level summary instead.
struct ZipEntry: Identifiable, Hashable, Sendable {
    let path: String

    var id: String { path }
    var isDirectory: Bool { path.hasSuffix("/") }

    /// Last component of the path. Used as the display label so deeply
    /// nested rows don't blow out the narrow preview pane.
    var displayName: String {
        let trimmed = isDirectory ? String(path.dropLast()) : path
        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }

    /// Indent depth in the listing — one step per `/` segment. Directories
    /// at the same level as a file render at the same depth.
    var depth: Int {
        let stripped = isDirectory ? String(path.dropLast()) : path
        return max(0, stripped.split(separator: "/").count - 1)
    }
}

/// Wraps `/usr/bin/unzip` for read-only previewing — listing and
/// single-entry extraction. Both paths drain the stdout pipe in
/// chunks so a large entry doesn't block on a full pipe buffer; the
/// extract path caps at `extractCap` so a 5 GB zip doesn't try to
/// land in memory and the preview pane gives up gracefully instead.
enum ZipPreviewService {
    static let extractCap = 16 * 1024 * 1024

    /// One archive table of contents. Resolves on a utility-priority
    /// detached task so the main actor never blocks on the unzip
    /// invocation.
    static func list(archive: URL) async throws -> [ZipEntry] {
        let data = try await runUnzip(arguments: ["-Z", "-1", archive.path], cap: 4 * 1024 * 1024)
        let text = String(data: data, encoding: .utf8) ?? ""
        return
            text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { ZipEntry(path: String($0)) }
    }

    /// Complete bytes of a previewable entry. Oversized entries throw rather
    /// than passing partial image/PDF data to a decoder.
    struct ExtractionResult: Sendable {
        let data: Data
        let truncated: Bool
    }

    static func extract(archive: URL, entry: String) async throws -> ExtractionResult {
        // `entry` is passed to `unzip -p` as a match pattern. We do NOT
        // use `--` to terminate option parsing because Info-ZIP doesn't
        // honor it — a leading `-` is still read as an option flag.
        // Instead `literalZipPattern` glob-escapes the name so it can
        // only match itself (see helper for the leading-dash trick).
        let data = try await runUnzip(
            arguments: ["-p", archive.path, literalZipPattern(entry)],
            cap: extractCap
        )
        return ExtractionResult(data: data, truncated: false)
    }

    /// Escape Info-ZIP's glob syntax, including literal backslashes.
    /// A leading dash is a character class so it cannot become an option.
    static func literalZipPattern(_ entry: String) -> String {
        var result = ""
        for (index, char) in entry.enumerated() {
            switch char {
            case "*", "?", "[", "]", "\\":
                result.append("\\")
                result.append(char)
            case "-" where index == 0:
                result.append("[-]")
            default:
                result.append(char)
            }
        }
        return result
    }

    /// Cancellation is bridged explicitly because detached workers do not
    /// inherit the SwiftUI task's cancellation state.
    private static func runUnzip(arguments: [String], cap: Int) async throws -> Data {
        let token = ProcessRunner.Cancellation()
        return try await withTaskCancellationHandler {
            let result = try await Task.detached(priority: .utility) {
                try ProcessRunner.run(
                    executable: URL(fileURLWithPath: "/usr/bin/unzip"), arguments: arguments,
                    timeout: 30, outputLimit: cap, stopAtOutputLimit: true,
                    isCancelled: { token.isCancelled }
                ).stdout
            }.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            token.cancel()
        }
    }

    /// Best-effort sweep of leftover PDF-preview temp directories from a
    /// prior run that crashed or was force-quit before `cleanupPDFTemp`
    /// ran. Called once from `AppDelegate.applicationDidFinishLaunching`;
    /// matches the `mq-dir-zip-preview-*` naming used by
    /// `ZipPreviewView.decodedContent`.
    static func sweepLeftoverTempDirs() {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        guard
            let contents = try? fm.contentsOfDirectory(
                at: tmp,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return }
        for dir in contents where dir.lastPathComponent.hasPrefix("mq-dir-zip-preview-") {
            try? fm.removeItem(at: dir)
        }
    }
}
