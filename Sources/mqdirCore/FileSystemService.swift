import Foundation

struct FileSystemService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func enumerateDirectory(at url: URL, includingHidden: Bool = false) throws -> [FileEntry] {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isHiddenKey,
        ]

        var options: FileManager.DirectoryEnumerationOptions = []
        if !includingHidden {
            options.insert(.skipsHiddenFiles)
        }

        let urls = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: options
        )

        return try urls.map { childURL in
            let values = try childURL.resourceValues(forKeys: keys)
            let isDirectory = values.isDirectory ?? false
            let name = childURL.lastPathComponent

            return FileEntry(
                url: childURL,
                name: name,
                isDirectory: isDirectory,
                size: isDirectory ? nil : values.fileSize.map(Int64.init),
                modificationDate: values.contentModificationDate,
                kind: kind(for: childURL, isDirectory: isDirectory),
                isHidden: values.isHidden ?? name.hasPrefix(".")
            )
        }
    }

    /// Recursive name search rooted at `url`. Visits every descendant via
    /// `FileManager.enumerator`, keeping entries whose name matches `query`
    /// case-insensitively. Errors on individual children are skipped so the
    /// walk doesn't abort on a single inaccessible subfolder. The
    /// `isCancelled` callback is polled periodically so a caller can stop a
    /// long walk when a fresher query supersedes it.
    func enumerateMatching(
        root: URL,
        query: String,
        includingHidden: Bool = false,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> [FileEntry] {
        guard !query.isEmpty else { return [] }

        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isHiddenKey,
        ]

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includingHidden {
            options.insert(.skipsHiddenFiles)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: options,
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var results: [FileEntry] = []
        var visited = 0

        for case let childURL as URL in enumerator {
            // Cheap cancellation check; avoid per-item lock overhead on big trees.
            visited &+= 1
            if visited & 0xFF == 0, isCancelled() { return results }

            let name = childURL.lastPathComponent
            guard name.localizedCaseInsensitiveContains(query) else { continue }

            let values = try? childURL.resourceValues(forKeys: keys)
            let isDirectory = values?.isDirectory ?? false
            results.append(FileEntry(
                url: childURL,
                name: name,
                isDirectory: isDirectory,
                size: isDirectory ? nil : (values?.fileSize).map(Int64.init),
                modificationDate: values?.contentModificationDate,
                kind: kind(for: childURL, isDirectory: isDirectory),
                isHidden: values?.isHidden ?? name.hasPrefix(".")
            ))
        }

        return results
    }

    private func kind(for url: URL, isDirectory: Bool) -> String {
        if isDirectory {
            return "Folder"
        }

        let ext = url.pathExtension
        if ext.isEmpty {
            return "Document"
        }

        return "\(ext.uppercased()) Document"
    }
}
