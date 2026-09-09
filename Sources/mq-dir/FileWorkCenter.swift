import Combine
import Foundation

@MainActor
final class FileWorkJob: ObservableObject, Identifiable {
    enum State { case queued, running, finished, cancelled }
    let id = UUID()
    let request: FileWorkRequest
    let cancellation = ProcessRunner.Cancellation()
    @Published var undoneIDs: Set<UUID> = []
    @Published var state = State.queued
    private(set) var outcomes: [FileWorkOutcome] = []
    @Published private(set) var processedCount = 0
    private(set) var successCount = 0
    private(set) var failedCount = 0
    private(set) var skippedCount = 0
    private(set) var cancelledCount = 0
    var completion: (([FileWorkOutcome]) -> Void)?

    init(_ request: FileWorkRequest, completion: (([FileWorkOutcome]) -> Void)?) {
        self.request = request
        self.completion = completion
    }
    var isActive: Bool { state == .queued || state == .running }
    var undoReceipts: [FileUndoReceipt] { outcomes.compactMap(\.undoReceipt).filter { !undoneIDs.contains($0.id) } }
    var retrySources: [URL] {
        // Permanent deletion requires a fresh selection and confirmation.
        request.kind == .delete ? [] : outcomes.filter(\.needsRetry).flatMap(\.sources)
    }
    func record(_ outcome: FileWorkOutcome) {
        outcomes.append(outcome)
        switch outcome.status {
        case .succeeded: successCount += 1
        case .failed: failedCount += 1
        case .skipped: skippedCount += 1
        case .cancelled: cancelledCount += 1
        }
        processedCount += 1
    }
}

/// App-wide lifetime: switching or closing a tab does not lose file work.
@MainActor
final class FileWorkCenter: ObservableObject {
    static let shared = FileWorkCenter()
    typealias Executor = @Sendable (FileWorkRequest, [URL], ProcessRunner.Cancellation) -> FileWorkOutcome
    @Published private(set) var jobs: [FileWorkJob] = []
    @Published var isPresented = false
    private var worker: Task<Void, Never>?
    private let execute: Executor

    init(execute: @escaping Executor = { FileOperationService.perform($0, sources: $1, cancellation: $2) }) { self.execute = execute }

    @discardableResult
    func submit(_ request: FileWorkRequest, completion: (([FileWorkOutcome]) -> Void)? = nil) -> FileWorkJob? {
        guard !request.sources.isEmpty else { return nil }
        isPresented = true
        if let existing = jobs.first(where: { $0.isActive && $0.request == request }) {
            if let completion { existing.completion = completion }
            return existing
        }
        let job = FileWorkJob(request, completion: completion)
        jobs.append(job)
        // Preserve active jobs and a bounded history; no paths are persisted.
        if jobs.count > 50, let index = jobs.firstIndex(where: { !$0.isActive }) { jobs.remove(at: index) }
        startWorker()
        return job
    }

    func cancel(_ job: FileWorkJob) {
        job.cancellation.cancel()
        if job.state == .queued {
            for sources in job.request.units {
                job.record(FileWorkOutcome(sources: sources, destination: nil, status: .cancelled))
            }
            job.state = .cancelled
            job.completion?(job.outcomes)
        }
    }

    func retry(_ job: FileWorkJob) {
        guard !job.isActive, !job.retrySources.isEmpty else { return }
        var request = job.request
        request.sources = job.retrySources
        submit(request, completion: job.completion)
    }

    func undo(_ job: FileWorkJob) {
        guard !job.isActive, !job.undoReceipts.isEmpty else { return }
        let receipts = job.undoReceipts
        submit(FileWorkRequest(kind: .undo, sources: receipts.map(\.current), undoReceipts: receipts)) { outcomes in
            for outcome in outcomes where outcome.status == .succeeded {
                for receipt in receipts where outcome.sources.contains(receipt.current) { job.undoneIDs.insert(receipt.id) }
            }
        }
    }

    var lastUndoableJob: FileWorkJob? { jobs.reversed().first { !$0.isActive && !$0.undoReceipts.isEmpty } }

    func clearFinished() { jobs.removeAll { !$0.isActive } }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task {
            while let job = jobs.first(where: { $0.state == .queued }) {
                job.state = .running
                let execute = execute
                for sources in job.request.units {
                    let outcome: FileWorkOutcome
                    if job.cancellation.isCancelled {
                        outcome = FileWorkOutcome(sources: sources, destination: nil, status: .cancelled)
                    } else {
                        let request = job.request
                        let token = job.cancellation
                        outcome = await Task.detached(priority: .userInitiated) {
                            execute(request, sources, token)
                        }.value
                    }
                    job.record(outcome)
                    if outcome.status == .succeeded {
                        let folders = sources.map { $0.deletingLastPathComponent() }
                            + [outcome.destination?.deletingLastPathComponent()].compactMap { $0 }
                        FileSystemChange.post(folders: folders)
                    }
                }
                job.state = job.cancelledCount > 0 ? .cancelled : .finished
                job.completion?(job.outcomes)
                objectWillChange.send()
            }
            worker = nil
        }
    }
}
