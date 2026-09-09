import AppKit
import MarkdownUI
import SwiftUI

struct PreviewMarkdownImageProvider: ImageProvider {
    var allowRemoteImages = false

    @ViewBuilder
    func makeImage(url: URL?) -> some View {
        if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
        } else if let url, allowRemoteImages, Self.isWebURL(url) {
            DefaultImageProvider.default.makeImage(url: url)
        } else {
            Label("External image blocked", systemImage: "photo.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }
}

struct PreviewMarkdownInlineImageProvider: InlineImageProvider {
    var allowRemoteImages = false
    var remoteImage: (URL, String) async throws -> Image = {
        try await DefaultInlineImageProvider.default.image(with: $0, label: $1)
    }

    func image(with url: URL, label: String) async throws -> Image {
        if url.isFileURL, let image = NSImage(contentsOf: url) {
            return Image(nsImage: image)
        }
        guard allowRemoteImages, PreviewMarkdownImageProvider.isWebURL(url) else {
            throw URLError(.resourceUnavailable)
        }
        return try await remoteImage(url, label)
    }
}

/// Permission belongs to this document view, not to all future previews.
struct PreviewMarkdownDocument: View {
    let text: String
    let url: URL
    @State private var allowRemoteImages = false

    var body: some View {
        VStack(spacing: 0) {
            if !allowRemoteImages {
                HStack {
                    Text("External images are blocked.")
                    Spacer()
                    Button("Load external images") { allowRemoteImages = true }
                }
                .font(.caption)
                .padding(8)
            }
            ScrollView {
                Markdown(text, baseURL: url.deletingLastPathComponent())
                    .markdownImageProvider(PreviewMarkdownImageProvider(allowRemoteImages: allowRemoteImages))
                    .markdownInlineImageProvider(
                        PreviewMarkdownInlineImageProvider(allowRemoteImages: allowRemoteImages)
                    )
                    .markdownTheme(.gitHub)
                    .markdownTextStyle { FontSize(13) }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
