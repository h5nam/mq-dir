import Combine
import Foundation

@MainActor
final class IntegrationsSidebarModel: ObservableObject {
    @Published var provider: WorkspaceProvider {
        didSet {
            guard provider != oldValue else { return }
            cancellation?.cancel()
            generation = UUID()
            workspaces = []
            lastError = nil
            lastSyncDate = nil
            isSyncing = false
        }
    }
    @Published private(set) var workspaces: [IntegrationWorkspace] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSyncDate: Date?
    private var cancellation: ProcessRunner.Cancellation?
    private var generation = UUID()
    typealias Fetcher =
        @Sendable (WorkspaceProvider, URL?, URL, ProcessRunner.Cancellation) throws -> [IntegrationWorkspace]
    private let fetch: Fetcher

    init(
        provider: WorkspaceProvider = .cmux,
        fetch: @escaping Fetcher = {
            try WorkspaceIntegrationClient.fetch($0, executable: $1, home: $2, cancellation: $3)
        }
    ) {
        self.provider = provider
        self.fetch = fetch
    }

    func sync() async {
        guard !isSyncing else { return }
        let selected = provider
        let revision = UUID()
        generation = revision
        let token = ProcessRunner.Cancellation()
        cancellation = token
        isSyncing = true
        defer { if generation == revision { isSyncing = false } }
        let executable = WorkspaceIntegrationClient.executable(for: selected)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fetch = fetch
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try fetch(selected, executable, home, token)
            }.value
            guard generation == revision, provider == selected, !token.isCancelled else { return }
            // Session-based providers may have many sessions for one folder.
            var seen = Set<String>()
            workspaces = result.filter { seen.insert($0.currentDirectory).inserted }
            lastError = nil
            lastSyncDate = Date()
        } catch {
            guard generation == revision, provider == selected, !token.isCancelled else { return }
            lastError = error.localizedDescription
        }
    }
}
