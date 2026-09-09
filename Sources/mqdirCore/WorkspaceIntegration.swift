import Foundation

enum WorkspaceProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case cmux, orca, paseo, claudeDesktop, codexDesktop
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cmux: "cmux"
        case .orca: "Orca"
        case .paseo: "Paseo"
        case .claudeDesktop: "Claude Code Desktop"
        case .codexDesktop: "Codex Desktop"
        }
    }
    var sourceDescription: String {
        switch self {
        case .cmux: "Local cmux workspaces"
        case .orca: "Local Orca worktrees · up to 1,000"
        case .paseo: "Local Paseo daemon workspaces"
        case .claudeDesktop: "Claude Desktop Code session metadata · experimental adapter"
        case .codexDesktop: "Recent local Codex sessions · up to 2,000"
        }
    }
}

struct IntegrationWorkspace: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let currentDirectory: String
    var selected = false
}

enum WorkspaceMetadata {
    enum Failure: Error, LocalizedError {
        case malformed
        var errorDescription: String? { "The selected app returned an unsupported workspace format." }
    }
    static func validPath(_ value: Any?) -> String? {
        guard let path = value as? String, path.hasPrefix("/"), !path.contains("\0") else { return nil }
        return path
    }
    static func orca(_ data: Data) throws -> [IntegrationWorkspace] {
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            envelope["ok"] as? Bool == true,
            let result = envelope["result"] as? [String: Any],
            let rows = result["worktrees"] as? [[String: Any]]
        else { throw Failure.malformed }
        return rows.compactMap { row in
            guard row["hostId"] as? String == "local", row["isArchived"] as? Bool != true,
                let path = validPath(row["path"]), let id = row["worktreeId"] as? String
            else { return nil }
            return IntegrationWorkspace(
                id: "orca:" + id, title: row["displayName"] as? String ?? URL(fileURLWithPath: path).lastPathComponent,
                currentDirectory: path, selected: row["isActive"] as? Bool ?? false)
        }
    }
    static func paseo(_ data: Data) throws -> [IntegrationWorkspace] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw Failure.malformed
        }
        return rows.compactMap { row in
            guard let id = row["workspaceId"] as? String, let path = validPath(row["cwd"]) else { return nil }
            return IntegrationWorkspace(
                id: "paseo:" + id, title: row["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent,
                currentDirectory: path)
        }
    }
    static func claudeDesktop(_ data: Data) throws -> IntegrationWorkspace? {
        guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.malformed }
        guard row["isArchived"] as? Bool != true,
            let path = validPath(row["cwd"]), let id = row["sessionId"] as? String
        else { return nil }
        return IntegrationWorkspace(
            id: "claudeDesktop:" + id,
            title: row["title"] as? String ?? URL(fileURLWithPath: path).lastPathComponent, currentDirectory: path)
    }
    static func codex(_ rows: [[String: Any]]) -> [IntegrationWorkspace] {
        rows.compactMap { row in
            guard let id = row["id"] as? String, let path = validPath(row["cwd"]) else { return nil }
            return IntegrationWorkspace(
                id: "codexDesktop:" + id,
                title: row["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent, currentDirectory: path)
        }
    }
}
