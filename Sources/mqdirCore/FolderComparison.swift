import Foundation

struct FolderComparisonRow: Identifiable, Sendable {
    enum Status: String, Sendable {
        case leftOnly = "Only on left", rightOnly = "Only on right", different = "Different metadata"
        case same = "Same metadata", folder = "Folder — contents not compared"
    }
    let id: String
    let name: String
    let left: URL?
    let right: URL?
    let status: Status
}

enum FolderComparison {
    static func compare(left: URL, right: URL, cancellation: ProcessRunner.Cancellation) throws -> [FolderComparisonRow] {
        let service = FileSystemService()
        let leftEntries = try service.enumerateDirectory(at: left, includingHidden: true, isCancelled: { cancellation.isCancelled })
        let rightEntries = try service.enumerateDirectory(at: right, includingHidden: true, isCancelled: { cancellation.isCancelled })
        let a = Dictionary(leftEntries.map { (Data($0.name.utf8), $0) }, uniquingKeysWith: { _, last in last })
        let b = Dictionary(rightEntries.map { (Data($0.name.utf8), $0) }, uniquingKeysWith: { _, last in last })
        return Set(a.keys).union(b.keys).map { key in
            let left = a[key], right = b[key]
            let status: FolderComparisonRow.Status
            if left == nil { status = .rightOnly }
            else if right == nil { status = .leftOnly }
            else if left!.isDirectory && right!.isDirectory { status = .folder }
            else if left!.isDirectory != right!.isDirectory || left!.size != right!.size || left!.modificationDate != right!.modificationDate { status = .different }
            else { status = .same }
            return FolderComparisonRow(id: key.base64EncodedString(), name: (left ?? right)!.name,
                left: left?.url, right: right?.url, status: status)
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }
}
