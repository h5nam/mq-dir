import Foundation

enum FileChangeScope {
    static func affects(root: URL?, changedFolders: [URL]?, recursive: Bool) -> Bool {
        guard let root else { return false }
        guard let changedFolders else { return true }
        let base = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return changedFolders.contains { folder in
            let changed = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            if base.starts(with: changed) { return true }
            if changed.starts(with: base) { return recursive || changed.count == base.count + 1 }
            return false
        }
    }
}
