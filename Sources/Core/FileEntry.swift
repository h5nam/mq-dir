import Foundation

struct FileEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modificationDate: Date?
    let kind: String
    let isHidden: Bool

    var id: String {
        url.path
    }
}

enum FileEntrySortKey: String, CaseIterable, Sendable {
    case name
    case modified
    case size
    case kind
}

enum FileEntrySorter {
    static func sorted(
        _ entries: [FileEntry],
        by key: FileEntrySortKey,
        ascending: Bool
    ) -> [FileEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

            let comparison: ComparisonResult = switch key {
            case .name:
                lhs.name.localizedStandardCompare(rhs.name)
            case .modified:
                compareOptional(lhs.modificationDate, rhs.modificationDate)
            case .size:
                compareOptional(lhs.size, rhs.size)
            case .kind:
                lhs.kind.localizedStandardCompare(rhs.kind)
            }

            if comparison == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private static func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs < rhs { return .orderedAscending }
            if lhs > rhs { return .orderedDescending }
            return .orderedSame
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        }
    }
}

