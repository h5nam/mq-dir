import AppKit
import Foundation

@MainActor
enum WorkspaceIntegrationClient {
    static func applicationURL(for provider: WorkspaceProvider) -> URL? {
        let identifiers: [String]
        let names: [String]
        switch provider {
        case .cmux: return CmuxClient.appURL()
        case .orca:
            identifiers = ["com.stablyai.orca"]
            names = ["Orca"]
        case .paseo:
            identifiers = []
            names = ["Paseo"]
        case .claudeDesktop:
            identifiers = ["com.anthropic.claudefordesktop"]
            names = ["Claude"]
        case .codexDesktop:
            identifiers = ["com.openai.codex"]
            names = ["Codex"]
        }
        for id in identifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        }
        for folder in [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ] {
            for name in names {
                let url = folder.appendingPathComponent(name + ".app")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    static func executable(for provider: WorkspaceProvider) -> URL? {
        if provider == .cmux { return CmuxClient.locateBinary().map { URL(fileURLWithPath: $0) } }
        let command: String
        switch provider {
        case .orca: command = "orca"
        case .paseo: command = "paseo"
        case .codexDesktop: command = "codex"
        case .claudeDesktop, .cmux: return nil
        }
        if provider == .codexDesktop, let app = applicationURL(for: provider) {
            let candidate = app.appendingPathComponent("Contents/Resources/codex")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for directory in [
            "/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".bun/bin").path, home.appendingPathComponent(".npm-global/bin").path,
        ] {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: path.path) { return path }
        }
        return nil
    }

    nonisolated static func fetch(
        _ provider: WorkspaceProvider, executable: URL?, home: URL,
        cancellation: ProcessRunner.Cancellation
    ) throws -> [IntegrationWorkspace] {
        if cancellation.isCancelled { throw ProcessRunner.Failure.cancelled }
        if provider == .claudeDesktop {
            let root = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
            guard FileManager.default.fileExists(atPath: root.path) else { throw ConnectionError.missingMetadata }
            guard
                let files = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            else { throw ConnectionError.missingMetadata }
            var results: [IntegrationWorkspace] = []
            for case let url as URL in files {
                if cancellation.isCancelled { throw ProcessRunner.Failure.cancelled }
                guard url.pathExtension == "json", url.lastPathComponent.hasPrefix("local_") else { continue }
                let text = try PreviewTextLoader.load(at: url, maximumBytes: 8 * 1024 * 1024)
                if let workspace = try WorkspaceMetadata.claudeDesktop(Data(text.utf8)) { results.append(workspace) }
            }
            return results
        }
        guard let executable else { throw ConnectionError.missingCLI(provider.title) }
        if provider == .cmux {
            return try CmuxClient.listWorkspaces().compactMap { workspace in
                guard let path = WorkspaceMetadata.validPath(workspace.currentDirectory) else { return nil }
                return IntegrationWorkspace(
                    id: "cmux:" + workspace.id, title: workspace.title,
                    currentDirectory: path, selected: workspace.selected)
            }
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        if provider == .codexDesktop {
            // The Desktop default profile, not an enclosing agent's account override.
            environment["CODEX_HOME"] = home.appendingPathComponent(".codex").path
            return try CodexWorkspaceReader.read(
                executable: executable, environment: environment, cancellation: cancellation)
        }
        let arguments =
            provider == .orca
            ? ["worktree", "ps", "--limit", "1000", "--json"]
            : ["--host", "127.0.0.1:6767", "workspace", "ls", "--json"]
        let data: Data
        do {
            data = try ProcessRunner.run(
                executable: executable, arguments: arguments, timeout: 12,
                outputLimit: 8 * 1024 * 1024, stopAtOutputLimit: true,
                isCancelled: { cancellation.isCancelled }, environment: environment
            ).stdout
        } catch ProcessRunner.Failure.exited(let code, _) {
            throw ConnectionError.unavailable(provider.title, code)
        }
        return try provider == .orca ? WorkspaceMetadata.orca(data) : WorkspaceMetadata.paseo(data)
    }

    enum ConnectionError: Error, LocalizedError {
        case missingCLI(String)
        case missingMetadata
        case unavailable(String, Int32)
        var errorDescription: String? {
            switch self {
            case .missingCLI(let app): "The \(app) CLI was not found. Install its CLI to sync local workspaces."
            case .unavailable(let app, let code):
                "\(app) could not provide workspaces (exit \(code)). Open the app or local daemon and retry Sync."
            case .missingMetadata:
                "No Claude Desktop Code session metadata was found. Open a local Code session in Claude first."
            }
        }
    }
}
