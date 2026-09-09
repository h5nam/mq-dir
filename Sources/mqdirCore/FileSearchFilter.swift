import Foundation

enum FileSearchCategory: String, Codable, CaseIterable, Sendable {
    case all, images, documents, archives, code, media
    var title: String { rawValue.capitalized }
    var extensions: Set<String> {
        switch self {
        case .all: []
        case .images: ["png", "jpg", "jpeg", "webp", "gif", "heic", "tif", "tiff", "svg"]
        case .documents: ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "md", "txt", "rtf", "hwp", "hwpx"]
        case .archives: ["zip", "tar", "gz", "tgz", "7z", "rar"]
        case .code: ["swift", "py", "js", "ts", "jsx", "tsx", "rs", "go", "html", "css", "json", "yaml", "yml"]
        case .media: ["mp4", "mov", "mkv", "mp3", "wav", "m4a", "aiff"]
        }
    }
}

struct FileSearchFilter: Codable, Equatable, Sendable {
    var category = FileSearchCategory.all
    var modifiedWithinDays: Int? = nil
    var filesOnly = false
    var isActive: Bool { category != .all || modifiedWithinDays != nil || filesOnly }

    func matches(_ entry: FileEntry, now: Date = Date()) -> Bool {
        if (filesOnly || category != .all) && entry.isDirectory { return false }
        if category != .all && !category.extensions.contains(entry.url.pathExtension.lowercased()) { return false }
        if let days = modifiedWithinDays {
            guard days > 0, let modified = entry.modificationDate,
                  modified >= now.addingTimeInterval(-Double(days) * 86400) else { return false }
        }
        return true
    }
}

struct SavedFileSearch: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var query: String
    var filter: FileSearchFilter
    var projectScope = false
}

final class FileSearchDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var errors = 0
    func recordError() { lock.lock(); defer { lock.unlock() }; errors += 1 }
    var errorCount: Int { lock.lock(); defer { lock.unlock() }; return errors }
}
