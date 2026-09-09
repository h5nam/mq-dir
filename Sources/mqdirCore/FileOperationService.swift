import Foundation

/// Stateless filesystem mechanics for the destructive / mutating file
/// operations the browser pane exposes (paste, duplicate, drop, trash,
/// permanent delete, compress, extract, new folder, rename). Pure
/// Foundation, `@Sendable`-safe, no AppKit / NotificationCenter / main
/// actor — the view model keeps the UI side effects (NSAlert presentation,
/// `.mqdirFileSystemChanged` broadcasts, pasteboard reads, selection state,
/// stderr logging) and calls in here for the actual disk work.
///
/// Per-item operations capture failures as `[(URL, Error)]` and keep going
/// past an individual error so a partial selection never aborts the whole
/// batch. Callers decide how to present (alert, stderr log, …).
public enum FileOperationService {

    // MARK: Collision-rename (unified)

    /// The single collision-rename primitive. Returns the first
    /// non-existing URL under `folder` formed from `stem` (+ optional
    /// `extension`), trying `stem`, then `stem 2`, `stem 3`, … up to
    /// `cap`. On exhaustion returns `nil` so the caller can apply its own
    /// fallback (timestamp, original target, …) — the four legacy helpers
    /// disagreed on that fallback, so it stays caller-owned.
    ///
    /// `includePrimary` controls whether the bare `stem` (n == 1) is
    /// offered first. Paste/duplicate/drop always start from " 2" because
    /// the conflict that triggered the rename already proved the bare name
    /// is taken; compress/extract try the bare `<stem>.zip` / `<stem>`
    /// first because they call in unconditionally.
    ///
    /// `fileExists` is injected for testability and defaults to
    /// `FileManager.default`. The unified cap is **999** (the higher of the
    /// two legacy caps — paste/duplicate used 500, the rest used 999).
    public static func uniqueDestination(
        in folder: URL,
        stem: String,
        extension ext: String = "",
        includePrimary: Bool,
        cap: Int = 999,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        func candidate(_ suffixed: String) -> URL {
            folder.appendingPathComponent(
                ext.isEmpty ? suffixed : "\(suffixed).\(ext)"
            )
        }
        if includePrimary {
            let primary = candidate(stem)
            if !fileExists(primary.path) { return primary }
        }
        guard cap >= 2 else { return nil }
        for n in 2...cap {
            let c = candidate("\(stem) \(n)")
            if !fileExists(c.path) { return c }
        }
        return nil
    }

    /// Conflict-rename for an existing source URL being copied/moved into
    /// `folder` (paste / duplicate / drop). Splits the source's
    /// stem/extension, then funnels through `uniqueDestination`. Starts
    /// from " 2" (the bare name is the conflict that triggered this) and
    /// falls back to a `stem-<timestamp>.ext` name on cap exhaustion —
    /// matching the legacy `uniqueDestination(for:in:)` exactly.
    public static func conflictRenamedDestination(
        for source: URL,
        in folder: URL,
        cap: Int = 999,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        now: () -> Date = Date.init
    ) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        if let resolved = uniqueDestination(
            in: folder,
            stem: stem,
            extension: ext,
            includePrimary: false,
            cap: cap,
            fileExists: fileExists
        ) {
            return resolved
        }
        let stamp = Int(now().timeIntervalSince1970)
        let fallback = ext.isEmpty ? "\(stem)-\(stamp)" : "\(stem)-\(stamp).\(ext)"
        return folder.appendingPathComponent(fallback)
    }

    /// New-folder / generic-target collision rename: appends " 2", " 3", …
    /// before the extension of `target` itself. Returns `target` unchanged
    /// on exhaustion — matching the legacy instance `uniqueDestination(for:)`.
    public static func uniqueTargetDestination(
        for target: URL,
        cap: Int = 999,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        guard fileExists(target.path) else { return target }
        let folder = target.deletingLastPathComponent()
        let stem = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        if let resolved = uniqueDestination(
            in: folder,
            stem: stem,
            extension: ext,
            includePrimary: false,
            cap: cap,
            fileExists: fileExists
        ) {
            return resolved
        }
        return target
    }

    /// `<stem>.zip`, then `<stem> 2.zip`, … under `parent`. Falls back to
    /// `<stem> <timestamp>.zip` on cap exhaustion — matching the legacy
    /// `uniqueZipDestination(in:stem:)` (space before the stamp, not dash).
    public static func uniqueZipDestination(
        in parent: URL,
        stem: String,
        cap: Int = 999,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        now: () -> Date = Date.init
    ) -> URL {
        if let resolved = uniqueDestination(
            in: parent,
            stem: stem,
            extension: "zip",
            includePrimary: true,
            cap: cap,
            fileExists: fileExists
        ) {
            return resolved
        }
        let stamp = Int(now().timeIntervalSince1970)
        return parent.appendingPathComponent("\(stem) \(stamp).zip")
    }

    /// Extraction-folder naming: `stem`, then `stem 2`, … under `parent`.
    /// Falls back to `stem <timestamp>` on cap exhaustion — matching the
    /// legacy `uniqueExtractionDirectory(in:stem:)`.
    public static func uniqueExtractionDirectory(
        in parent: URL,
        stem: String,
        cap: Int = 999,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        now: () -> Date = Date.init
    ) -> URL {
        if let resolved = uniqueDestination(
            in: parent,
            stem: stem,
            extension: "",
            includePrimary: true,
            cap: cap,
            fileExists: fileExists
        ) {
            return resolved
        }
        let stamp = Int(now().timeIntervalSince1970)
        return parent.appendingPathComponent("\(stem) \(stamp)")
    }

    // MARK: Copy / move / duplicate / delete

    /// Copy or move `sources` into `destinationFolder` with Finder-style
    /// conflict auto-rename and self-/descendant-drop rejection. Mirrors
    /// the old `acceptDrop` / `pasteFromPasteboard` detached-loop body.
    ///
    /// Per source:
    ///   - skips a no-op self-drop (`source == dest` after standardizing),
    ///   - auto-renames on an existing destination via `conflictRenamedDestination`,
    ///   - rejects dropping a folder into itself or any descendant
    ///     (checked against the *post-rename* dest),
    ///   - `move == false` copies, otherwise moves.
    ///
    /// Returns the per-item failures; the operation continues past each.
    @discardableResult
    public static func transfer(
        _ sources: [URL],
        into destinationFolder: URL,
        move: Bool,
        normalizeHangul: Bool = false,
        fileManager: FileManager = .default
    ) -> [(URL, Error)] {
        var failures: [(URL, Error)] = []
        for source in sources {
            var dest = destinationFolder.appendingPathComponent(source.lastPathComponent)
            if source.standardizedFileURL == dest.standardizedFileURL { continue }
            if fileManager.fileExists(atPath: dest.path) {
                dest = conflictRenamedDestination(
                    for: source,
                    in: destinationFolder,
                    fileExists: { fileManager.fileExists(atPath: $0) }
                )
            }
            if dest.path.hasPrefix(source.path + "/") { continue }
            do {
                if move {
                    try fileManager.moveItem(at: source, to: dest)
                } else {
                    try fileManager.copyItem(at: source, to: dest)
                }
                normalizeIfRequested(dest, enabled: normalizeHangul)
            } catch {
                failures.append((source, error))
            }
        }
        return failures
    }

    /// A drag defaults to move only when both volumes are known and equal.
    /// Check each source independently because a drag can span volumes.
    static func transferDroppedItems(
        _ sources: [URL],
        into destinationFolder: URL,
        forceCopy: Bool,
        normalizeHangul: Bool = false,
        volumeIdentifier: (URL) -> AnyHashable? = {
            (try? $0.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? AnyHashable
        }
    ) -> [(URL, Error)] {
        let destinationVolume = volumeIdentifier(destinationFolder)
        return sources.flatMap { source in
            // Moving a symlink moves the link, so use its parent's volume.
            let sourceVolume = volumeIdentifier(source.deletingLastPathComponent())
            let sameVolume = sourceVolume != nil && sourceVolume == destinationVolume
            return transfer([source], into: destinationFolder, move: !forceCopy && sameVolume,
                            normalizeHangul: normalizeHangul)
        }
    }

    /// After a successful copy/move/duplicate, rename the resulting file
    /// to NFC form on disk when `enabled` and its name is decomposed
    /// Hangul (NFD). A rename failure is swallowed — the transfer itself
    /// already succeeded, so the worst case is the on-disk name stays NFD
    /// rather than the whole operation reporting failure.
    private static func normalizeIfRequested(_ url: URL, enabled: Bool) {
        guard enabled else { return }
        _ = HangulNFCFilename.renameToNFC(url)
    }

    /// Duplicate each source in place with a Finder-style " 2" / " 3"
    /// suffix. Mirrors the old `duplicate(_:)` detached-loop body.
    /// Returns per-item failures; continues past each.
    @discardableResult
    public static func duplicate(
        _ sources: [URL],
        normalizeHangul: Bool = false,
        fileManager: FileManager = .default
    ) -> [(URL, Error)] {
        var failures: [(URL, Error)] = []
        for source in sources {
            let parent = source.deletingLastPathComponent()
            let dest = conflictRenamedDestination(
                for: source,
                in: parent,
                fileExists: { fileManager.fileExists(atPath: $0) }
            )
            do {
                try fileManager.copyItem(at: source, to: dest)
                normalizeIfRequested(dest, enabled: normalizeHangul)
            } catch {
                failures.append((source, error))
            }
        }
        return failures
    }

    /// Move each URL to the trash via `FileManager.trashItem`. Mirrors the
    /// old `moveToTrash(_:)` loop. Returns per-item failures; continues
    /// past each. (The AppKit recycle-sound path stays in the VM — this is
    /// pure Foundation.)
    @discardableResult
    public static func moveToTrash(
        _ urls: [URL],
        fileManager: FileManager = .default
    ) -> [(URL, Error)] {
        var failures: [(URL, Error)] = []
        for url in urls {
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failures.append((url, error))
            }
        }
        return failures
    }

    /// Permanently remove each URL via `FileManager.removeItem`. Mirrors
    /// the old `permanentlyDelete(_:)` detached loop. Returns per-item
    /// failures; continues past each. The destructive NSAlert confirm
    /// stays in the VM.
    @discardableResult
    public static func permanentlyDelete(
        _ urls: [URL],
        fileManager: FileManager = .default
    ) -> [(URL, Error)] {
        var failures: [(URL, Error)] = []
        for url in urls {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                failures.append((url, error))
            }
        }
        return failures
    }

    // MARK: New folder / rename

    /// Create a fresh directory at `target`, auto-renaming on collision
    /// (" 2", " 3", …). Returns the URL that was actually created, or
    /// throws if `createDirectory` fails. Mirrors `createNewFolder`'s
    /// mechanics minus the reload.
    @discardableResult
    public static func createDirectory(
        at target: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let resolved = uniqueTargetDestination(
            for: target,
            fileExists: { fileManager.fileExists(atPath: $0) }
        )
        try fileManager.createDirectory(at: resolved, withIntermediateDirectories: false)
        return resolved
    }

    /// Error surfaced by `rename` when the destination already exists.
    public enum RenameError: Error, Equatable, LocalizedError {
        case destinationExists(name: String)
        case invalidName

        public var errorDescription: String? {
            switch self {
            case .destinationExists(let name):
                return "An item named '\(name)' already exists in this folder."
            case .invalidName:
                return "Enter a file name without slashes. The names '.' and '..' are not allowed."
            }
        }
    }

    /// Rename `source` to `newName` within its parent folder. Refuses to
    /// overwrite an existing sibling (throws `RenameError.destinationExists`).
    /// Returns the new URL on success. Mirrors `commitRename`'s mechanics;
    /// the trim / empty / unchanged guards stay in the VM (they touch
    /// `renameDraft` / `entry.name`).
    @discardableResult
    public static func rename(
        _ source: URL,
        to newName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard !newName.isEmpty, newName != ".", newName != "..",
              !newName.contains("/"), !newName.contains("\0") else {
            throw RenameError.invalidName
        }
        let dest = source.deletingLastPathComponent().appendingPathComponent(newName)
        guard !fileManager.fileExists(atPath: dest.path) else {
            throw RenameError.destinationExists(name: newName)
        }
        try fileManager.moveItem(at: source, to: dest)
        return dest
    }

    // MARK: Compress

    /// Why a compress request can't run before any Process spins up.
    public enum CompressError: Error, Equatable, LocalizedError {
        /// Selection spanned more than one parent folder — zip's relative
        /// pathing assumes a single working directory.
        case crossFolder
        public var errorDescription: String? { "Select items from one folder to compress them together." }
    }

    /// The `stem` Finder would name a compress destination: a single
    /// directory keeps its name, a single file drops its extension, and a
    /// multi-selection becomes "Archive".
    public static func compressionStem(forSingleDirectory isDirectory: Bool, url: URL) -> String {
        isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    /// Validate + plan a compress of `urls` (paired with their `isDirectory`
    /// flags) into a single .zip in their shared parent. Rejects a
    /// cross-folder selection (`CompressError.crossFolder`). Returns the
    /// parent folder, the chosen unique `.zip` destination, and the source
    /// names (last path components) to pass to `runCompression`.
    public static func planCompression(
        urls: [(url: URL, isDirectory: Bool)],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        now: () -> Date = Date.init
    ) throws -> (parent: URL, destination: URL, sourceNames: [String])? {
        guard let first = urls.first else { return nil }
        let parent = first.url.deletingLastPathComponent()
        let sameParent = urls.allSatisfy { $0.url.deletingLastPathComponent() == parent }
        guard sameParent else { throw CompressError.crossFolder }

        let stem: String
        if urls.count == 1 {
            stem = compressionStem(forSingleDirectory: first.isDirectory, url: first.url)
        } else {
            stem = "Archive"
        }
        let destination = uniqueZipDestination(
            in: parent,
            stem: stem,
            fileExists: fileExists,
            now: now
        )
        return (parent, destination, urls.map { $0.url.lastPathComponent })
    }

    /// Build in a private sibling directory, then publish without overwriting
    /// any existing destination. Failed/cancelled work is never published.
    public static func runCompression(
        parent: URL,
        sources: [String],
        destination: URL,
        timeout: TimeInterval = 3600,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws {
        if isCancelled() { throw ProcessRunner.Failure.cancelled }
        guard !sources.isEmpty, sources.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\0")
        }) else { throw RenameError.invalidName }
        let staging = try makeArchiveStaging(for: destination)
        defer { removeArchiveStaging(staging) }
        let archive = staging.appendingPathComponent("archive.zip")
        _ = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-r", "-y", "-q", archive.path] + sources.map { "./" + $0 },
            directory: parent, timeout: timeout, isCancelled: isCancelled
        )
        if isCancelled() { throw ProcessRunner.Failure.cancelled }
        try FileManager.default.moveItem(at: archive, to: destination)
    }

    private static func makeArchiveStaging(for destination: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: destination.path) {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path])
        }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".mqdir-archive-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        return staging
    }

    private static func removeArchiveStaging(_ staging: URL) {
        do { try FileManager.default.removeItem(at: staging) }
        catch {
            FileHandle.standardError.write(Data("[mq-dir archive] Could not remove staging folder \(staging.path): \(error)\n".utf8))
        }
    }

    // MARK: Extract

    /// Archive kinds we recognize; drives both the extension test in
    /// `archiveKind(for:)` and the tool/argument selection in
    /// `runExtraction`.
    public enum ArchiveKind: Sendable {
        case zip
        case tar
        case tarGz
    }

    /// Map a URL's extension to a known archive kind, case-insensitive.
    /// `.tgz` and `.tar.gz` are gzip-compressed tar; `.tar.gz` is detected
    /// from the full filename, not just the last extension.
    public static func archiveKind(for url: URL) -> ArchiveKind? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".zip") { return .zip }
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .tarGz }
        if name.hasSuffix(".tar") { return .tar }
        return nil
    }

    /// Strip the archive extension so the extraction folder is named after
    /// the contents. `.tar.gz` loses both extensions; everything else loses
    /// the last one.
    public static func archiveStem(for url: URL, kind: ArchiveKind) -> String {
        let base = url.lastPathComponent
        switch kind {
        case .tarGz where base.lowercased().hasSuffix(".tar.gz"):
            return String(base.dropLast(".tar.gz".count))
        case .zip, .tar, .tarGz:
            return url.deletingPathExtension().lastPathComponent
        }
    }

    /// True when every entry's URL is a recognized archive *and* none is a
    /// directory. Empty input returns false. Takes `(url, isDirectory)`
    /// pairs so the pure logic lives here while `FileEntry` stays in the VM.
    public static func canExtract(_ entries: [(url: URL, isDirectory: Bool)]) -> Bool {
        guard !entries.isEmpty else { return false }
        return entries.allSatisfy { entry in
            archiveKind(for: entry.url) != nil && !entry.isDirectory
        }
    }

    /// Extract privately and publish only after the tool exits successfully.
    public static func runExtraction(
        kind: ArchiveKind,
        archive: URL,
        destination: URL,
        timeout: TimeInterval = 3600,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws {
        if isCancelled() { throw ProcessRunner.Failure.cancelled }
        let staging = try makeArchiveStaging(for: destination)
        defer { removeArchiveStaging(staging) }
        let contents = staging.appendingPathComponent("contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: false)
        let executable: String
        let arguments: [String]
        switch kind {
        case .zip:
            executable = "/usr/bin/ditto"
            arguments = ["-x", "-k", archive.path, contents.path]
        case .tar:
            executable = "/usr/bin/tar"
            arguments = ["-xf", archive.path, "-C", contents.path]
        case .tarGz:
            executable = "/usr/bin/tar"
            arguments = ["-xzf", archive.path, "-C", contents.path]
        }
        _ = try ProcessRunner.run(executable: URL(fileURLWithPath: executable), arguments: arguments,
                                  timeout: timeout, isCancelled: isCancelled)
        if isCancelled() { throw ProcessRunner.Failure.cancelled }
        try FileManager.default.moveItem(at: contents, to: destination)
    }

    /// Extract one archive into a fresh sibling folder named after its
    /// stem (with " 2", " 3", … collision rename). Bundles
    /// `archiveStem` + `uniqueExtractionDirectory` + `runExtraction` so the
    /// VM's batch loop stays a thin per-archive call. Throws on failure.
    /// Returns the destination folder that was created.
    @discardableResult
    public static func extract(
        archive: URL,
        kind: ArchiveKind,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        timeout: TimeInterval = 3600,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> URL {
        let parent = archive.deletingLastPathComponent()
        let stem = archiveStem(for: archive, kind: kind)
        let dest = uniqueExtractionDirectory(in: parent, stem: stem, fileExists: fileExists)
        try runExtraction(kind: kind, archive: archive, destination: dest, timeout: timeout, isCancelled: isCancelled)
        return dest
    }
}
