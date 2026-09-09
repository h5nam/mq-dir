import AppKit
import SwiftUI

struct FolderComparisonRequest: Identifiable {
    let id = UUID()
    let left: URL
    let right: URL
}

struct FolderComparisonView: View {
    let request: FolderComparisonRequest
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [FolderComparisonRow] = []
    @State private var error: String?
    @State private var loading = true
    @State private var revision = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Compare folders").font(.headline)
                Spacer()
                Button("Refresh") { revision = UUID() }
                Button("Close") { dismiss() }
            }
            Text("Left: " + request.left.path).textSelection(.enabled)
            Text("Right: " + request.right.path).textSelection(.enabled)
            Text("Snapshot of names, sizes and dates. File contents and nested folders are not compared.")
                .font(.caption).foregroundStyle(.secondary)
            if loading { ProgressView() }
            else if let error { Text(error).foregroundStyle(.red) }
            else if rows.isEmpty { Text("Both folders are empty.") }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(rows) { row in
                            HStack {
                                Text(row.name).lineLimit(1).frame(width: 230, alignment: .leading)
                                Text(row.status.rawValue).foregroundStyle(row.status == .different ? .orange : .secondary)
                                Spacer()
                                if let left = row.left { Button("Left") { NSWorkspace.shared.activateFileViewerSelecting([left]) } }
                                if let right = row.right { Button("Right") { NSWorkspace.shared.activateFileViewerSelecting([right]) } }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 680, idealWidth: 800, minHeight: 400, idealHeight: 520)
        .task(id: revision) { await load() }
    }

    @MainActor private func load() async {
        loading = true
        error = nil
        let token = ProcessRunner.Cancellation()
        await withTaskCancellationHandler {
            do {
                let left = request.left, right = request.right
                let result = try await Task.detached(priority: .userInitiated) {
                    try FolderComparison.compare(left: left, right: right, cancellation: token)
                }.value
                guard !Task.isCancelled else { return }
                rows = result
                loading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                loading = false
            }
        } onCancel: { token.cancel() }
    }
}
