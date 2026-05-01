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
