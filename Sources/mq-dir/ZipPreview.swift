import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Preview view

/// Right-side preview pane for a selected `.zip`. Top half is a
/// scrollable listing of the archive's contents (one row per
/// `ZipEntry`, indented by depth). Bottom half is a context-sensitive
/// preview of the selected entry: text/Markdown for source code &
/// docs, NSImage for images, PDFKit for embedded PDFs. Anything we
/// can't decode in-memory falls back to a "Use Extract to view"
/// hint — the existing ditto/tar context-menu action stays the
/// escape hatch.
struct ZipPreviewView: View {
    let url: URL

    @State private var entries: [ZipEntry] = []
    @State private var listError: String?
    @State private var loadingList = false
    @State private var selected: ZipEntry?
    @State private var content: ZipPreviewContent = .idle
    /// PDF preview needs a real file URL because `PDFDocument(url:)`
    /// and `PDFView` won't render in-memory data without first
    /// landing it on disk; the temp file is recreated per selection
    /// and cleaned up when the view goes away.
    @State private var pdfTempURL: URL?

    var body: some View {
        VSplitView {
            listing
                .frame(minHeight: 120)
            previewArea
                .frame(minHeight: 80)
        }
        .task(id: url) { await reloadListing() }
        .task(id: ContentRequest(archive: url, entry: selected)) {
            await loadContent(for: selected)
        }
        .onDisappear { cleanupPDFTemp() }
    }

    private struct ContentRequest: Hashable {
        let archive: URL
        let entry: ZipEntry?
    }

    // MARK: Listing

    private var listing: some View {
        Group {
            if loadingList {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let listError {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                    Text("Couldn't read archive")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Color.label)
                    Text(listError)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.labelSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                Text("Empty archive")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.labelTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // SwiftUI's `List(selection:)` does not reliably
                // respond to clicks inside a SwiftUI macOS host —
                // the rest of the app uses ScrollView+ForEach+Button
                // for the same reason. Mirror that pattern so a tap
                // actually flips `selected`.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            zipRow(entry)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Theme.Color.paneBg)
            }
        }
    }

    private func zipRow(_ entry: ZipEntry) -> some View {
        let isSelected = selected == entry
        return HStack(spacing: 6) {
            Spacer().frame(width: CGFloat(entry.depth) * 12)
            Image(systemName: entry.isDirectory ? "folder" : "doc")
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? .white : Theme.Color.labelSecondary)
            Text(entry.displayName)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .white : Theme.Color.label)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? Theme.Color.selection : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        // Mirror the BrowserPaneView row pattern — `Button(...).buttonStyle(.plain)`
        // does not reliably receive clicks inside SwiftUI scroll hosts on
        // macOS, so the rest of the app uses onTapGesture on a content-shape
        // background. Keep the same convention here.
        .onTapGesture {
            selected = entry
        }
    }

    // MARK: Preview area

    @ViewBuilder
    private var previewArea: some View {
        switch content {
        case .idle:
            placeholder("Select an entry to preview")
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .text(let string, let truncated):
            ScrollView {
                Text(string)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Color.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Theme.Color.paneBg)
            .overlay(alignment: .topTrailing) {
                if truncated {
                    truncationBadge
                        .padding(8)
                }
            }
        case .image(let image):
            ZStack {
                Theme.Color.paneBg
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            }
        case .pdf(let url):
            PDFPreview(url: url)
        case .directory:
            placeholder("Folder — pick a file inside to preview")
        case .unsupported(let summary):
            VStack(spacing: 6) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Color.labelTertiary)
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                Text("Use Extract from the right-click menu to open it.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.labelTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
                Text("Couldn't extract entry")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.label)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var truncationBadge: some View {
        Text("Truncated at \(ZipPreviewService.extractCap / (1024 * 1024)) MB")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Color.accent.opacity(0.85), in: Capsule())
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.labelTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Loaders

    @MainActor
    private func reloadListing() async {
        guard !Task.isCancelled else { return }
        loadingList = true
        listError = nil
        selected = nil
        content = .idle
        cleanupPDFTemp()
        do {
            let result = try await ZipPreviewService.list(archive: url)
            guard !Task.isCancelled else { return }
            entries = result
            loadingList = false
            selected = result.first(where: { !$0.isDirectory })
        } catch {
            guard !Task.isCancelled else { return }
            entries = []
            listError = error.localizedDescription
            loadingList = false
        }
    }

    @MainActor
    private func loadContent(for entry: ZipEntry?) async {
        guard !Task.isCancelled else { return }
        cleanupPDFTemp()
        guard let entry else { content = .idle; return }
        if entry.isDirectory { content = .directory; return }
        content = .loading
        do {
            let result = try await ZipPreviewService.extract(archive: url, entry: entry.path)
            guard !Task.isCancelled else { return }
            // No suspension between the final cancellation check, temp-file
            // ownership update and publishing the new preview.
            content = decodedContent(for: entry, data: result.data, truncated: result.truncated)
        } catch {
            guard !Task.isCancelled else { return }
            content = .error(error.localizedDescription)
        }
    }

    /// Map raw extracted bytes onto a renderable preview shape.
    /// Image / PDF / text are decoded inline; everything else falls
    /// through to the Extract hint so the user knows the next step.
    /// Runs on the main actor so the PDF branch can mutate the
    /// `pdfTempURL` @State synchronously and ordered against
    /// `cleanupPDFTemp`.
    @MainActor
    private func decodedContent(
        for entry: ZipEntry,
        data: Data,
        truncated: Bool
    ) -> ZipPreviewContent {
        let ext = (entry.path as NSString).pathExtension.lowercased()
        if Self.imageExtensions.contains(ext), let image = NSImage(data: data) {
            return .image(image)
        }
        if ext == "pdf" {
            // PDFKit is happiest with a file URL on disk. Drop the
            // bytes into a temp file scoped to this preview view so
            // teardown can reliably clean it up.
            do {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mq-dir-zip-preview-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let tempURL = tempDir.appendingPathComponent(entry.displayName.isEmpty ? "preview.pdf" : entry.displayName)
                try data.write(to: tempURL)
                // Replace any previous temp dir synchronously on the main
                // actor. Doing this via a detached `Task { @MainActor }`
                // previously let rapid PDF→PDF selections interleave with
                // `cleanupPDFTemp`, leaking the directory we were about to
                // overwrite. Clean up the specific dir we're replacing.
                if let previous = pdfTempURL, previous != tempURL {
                    try? FileManager.default.removeItem(at: previous.deletingLastPathComponent())
                }
                pdfTempURL = tempURL
                return .pdf(tempURL)
            } catch {
                return .error(error.localizedDescription)
            }
        }
        if let text = String(data: data, encoding: .utf8), looksLikeText(text) {
            return .text(text, truncated: truncated)
        }
        return .unsupported(summary: "No in-pane preview for \(ext.isEmpty ? "this entry" : ".\(ext)") files.")
    }

    /// Crude binary detector — if more than 1% of the sampled bytes
    /// are NUL or non-printable controls, treat as binary and skip
    /// the text path. Avoids dumping an executable's bytes into the
    /// monospace pane just because UTF-8 happened to decode it.
    private func looksLikeText(_ string: String) -> Bool {
        if string.isEmpty { return false }
        let sample = string.prefix(4_000)
        var bad = 0
        for scalar in sample.unicodeScalars {
            if scalar == "\0" { return false }
            if scalar.value < 0x20,
               scalar != "\n", scalar != "\r", scalar != "\t" {
                bad += 1
            }
        }
        // Cross-multiply instead of `bad < count / 100`: integer
        // division truncates to 0 for samples under 100 scalars, which
        // would misclassify every short text file as binary. `bad * 100
        // < count` keeps the same 1%-bad threshold without the divisor
        // collapsing on small inputs.
        return bad * 100 < sample.unicodeScalars.count
    }

    private func cleanupPDFTemp() {
        guard let url = pdfTempURL else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        pdfTempURL = nil
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "webp", "ico"
    ]
}

/// Discriminated union of every preview shape the bottom half of
/// `ZipPreviewView` can show. SwiftUI's `switch` on enum cases keeps
/// the conditional rendering tree simpler than carrying separate
/// optional state variables for each branch.
enum ZipPreviewContent: Equatable {
    case idle
    case loading
    case directory
    case text(String, truncated: Bool)
    case image(NSImage)
    case pdf(URL)
    case unsupported(summary: String)
    case error(String)
}
