import AppKit
import SwiftUI

struct MarkdownFilePreview: View {
    let url: URL
    @State private var text: String?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let text {
                PreviewMarkdownDocument(text: text, url: url)
            } else if let loadError {
                VStack(spacing: 8) {
                    Text(loadError).font(.caption).foregroundStyle(.secondary)
                    Button("Open in default app") { NSWorkspace.shared.open(url) }
                }
                .padding()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) { await load() }
    }

    @MainActor
    private func load() async {
        let token = ProcessRunner.Cancellation()
        text = nil
        loadError = nil
        await withTaskCancellationHandler {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try PreviewTextLoader.load(at: url, isCancelled: { token.isCancelled })
                }.value
                guard !Task.isCancelled else { return }
                text = loaded
            } catch {
                guard !Task.isCancelled else { return }
                loadError = error.localizedDescription
            }
        } onCancel: {
            token.cancel()
        }
    }
}
