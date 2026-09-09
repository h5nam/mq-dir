import SwiftUI

struct FileWorkPanel: View {
    @ObservedObject var center: FileWorkCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File operations").font(.headline)
                Spacer()
                Button("Clear finished") { center.clearFinished() }
                Button("Close") { center.isPresented = false }
            }
            if center.jobs.isEmpty {
                Text("No file operations yet").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(center.jobs.reversed()) { job in
                            FileWorkRow(job: job, center: center)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 540, idealWidth: 660, minHeight: 340, idealHeight: 500)
    }
}

private struct FileWorkRow: View {
    @ObservedObject var job: FileWorkJob
    let center: FileWorkCenter
    @State private var visibleCount = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(job.request.kind.title) · \(job.request.sources.count) item(s)").bold()
                Spacer()
                if job.isActive {
                    Button(job.request.kind == .compress || job.request.kind == .extract ? "Cancel" : "Stop after current item") {
                        center.cancel(job)
                    }
                } else {
                    if !job.retrySources.isEmpty { Button("Retry incomplete") { center.retry(job) } }
                    if !job.undoReceipts.isEmpty { Button("Undo") { center.undo(job) } }
                }
            }
            if job.isActive {
                ProgressView(value: Double(job.outcomes.count), total: Double(job.request.unitCount))
                Text(job.state == .queued ? "Queued" : "Processing \(job.outcomes.count + 1) of \(job.request.unitCount)")
            } else {
                Text("\(job.successCount) succeeded · \(job.failedCount) failed · \(job.skippedCount) skipped · \(job.cancelledCount) not processed")
            }
            if job.request.kind == .delete, job.failedCount > 0 {
                Text("Select the files again to retry permanent deletion.").font(.caption)
            }
            ForEach(Array(job.outcomes.prefix(visibleCount))) { result in
                HStack(alignment: .top) {
                    Text(result.sources.map(\.lastPathComponent).joined(separator: ", ")).lineLimit(2)
                    Spacer()
                    switch result.status {
                    case .succeeded:
                        if let destination = result.destination {
                            Text(destination.path).lineLimit(2).textSelection(.enabled)
                        } else { Text("Done") }
                    case .failed(let message): Text(message).foregroundStyle(.red).textSelection(.enabled)
                    case .skipped(let reason): Text(reason).foregroundStyle(.secondary)
                    case .cancelled: Text("Not processed").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            if job.outcomes.count > visibleCount {
                Button("Show more results") { visibleCount += 50 }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
