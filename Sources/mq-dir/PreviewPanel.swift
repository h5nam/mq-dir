import AppKit
import MarkdownUI
import PDFKit
import QuickLookUI
import SwiftUI

/// Right-side preview panel for the focused tab.
///
/// Three render paths, picked by selection state:
///   1. No selection / multi-selection / folder → custom summary view.
///   2. Markdown file (.md / .markdown / .mdown) → MarkdownUI for proper
///      GFM rendering (headings, lists, tables, code-with-highlight, …).
///   3. Anything else → `QLPreviewView`, which inherits the system Quick
///      Look generators (images, PDF, code, video, audio, office docs, …).
///
/// The panel is per-tab; toggling it persists in `FolderBrowserViewModel`
/// and is replayed on restart through `TabState.previewVisible`.
struct PreviewPanel: View {
    @ObservedObject var viewModel: FolderBrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.Color.separator)
            content
                .id(focusedEntry)
        }
        .background(Theme.Color.paneBg)
    }

    // MARK: Header (file name + size/modified)

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            if let entry = focusedEntry {
                FileRowIcon(entry: entry)
                Text(entry.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("—")
                    .foregroundStyle(Theme.Color.labelTertiary)
                Text(metadataLine(for: entry))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.labelSecondary)
            } else {
                Text("Preview")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.labelSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.Metrics.paneHeaderHeight)
    }

    private func metadataLine(for entry: FileEntry) -> String {
        let date = Self.dateFormatter.string(from: entry.modificationDate ?? Date())
        if let bytes = entry.size {
            return "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) · \(date)"
        }
        return date
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let selectedEntries = currentlySelectedEntries

        if selectedEntries.isEmpty {
            emptyState("Select a file to preview")
        } else if selectedEntries.count > 1 {
            multiSelectionSummary(selectedEntries)
        } else if let entry = selectedEntries.first {
            if entry.isDirectory {
                folderSummary(entry)
            } else if isMarkdown(entry.url) {
                markdownView(for: entry.url)
            } else if isPDF(entry.url) {
                // Embedded QLPreviewView pins multi-page PDFs to the
                // first page with no scroll/paging — known limitation
                // of QLPreviewView in SwiftUI hosts. PDFKit's PDFView
                // gives proper continuous-scroll paging out of the box.
                PDFPreview(url: entry.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isZip(entry.url) {
                // Quick Look has no zip generator on macOS, so the
                // default fallthrough rendered a generic icon. The
                // zip-aware path runs `unzip -Z -1` for the listing
                // and `unzip -p` for in-pane single-entry preview.
                ZipPreviewView(url: entry.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                QuickLookPreview(url: entry.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack {
            Spacer()
            Image(systemName: "eye.slash")
                .font(.system(size: 22))
                .foregroundStyle(Theme.Color.labelTertiary)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.labelTertiary)
                .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func multiSelectionSummary(_ entries: [FileEntry]) -> some View {
        let totalSize = entries.compactMap(\.size).reduce(0, +)
        return VStack(spacing: 6) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 22))
                .foregroundStyle(Theme.Color.labelSecondary)
            Text("\(entries.count) items selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.label)
            Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.labelSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func folderSummary(_ entry: FileEntry) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "folder.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Color.accent.opacity(0.85))
            Text(entry.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Color.label)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(entry.url.path)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Color.labelTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func markdownView(for url: URL) -> some View {
        MarkdownFilePreview(url: url)
    }

    // MARK: Selection helpers

    /// All entries currently selected in the focused tab. Routes through
    /// `viewModel.selectedEntries` so tree-mode selections (which live in
    /// `treeChildren`, not `entries`) resolve correctly — otherwise the
    /// preview pane stays empty for any expanded tree row.
    private var currentlySelectedEntries: [FileEntry] {
        viewModel.selectedEntries
    }

    /// Single-pick used by the header. Mirrors `currentlySelectedEntries`
    /// but returns nil when nothing — or multiple things — are selected.
    private var focusedEntry: FileEntry? {
        let entries = currentlySelectedEntries
        return entries.count == 1 ? entries.first : nil
    }

    private func isMarkdown(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown" || ext == "mdown"
    }

    private func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    private func isZip(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}

// MARK: - Quick Look bridge

/// PDFKit-based preview specifically for `.pdf` files. We can't keep
/// PDFs on `QLPreviewView` because that view, when hosted inside a
/// SwiftUI NSViewRepresentable, pins multi-page PDFs to the first
/// page and swallows scroll-wheel events — verified against
/// PDFs in the focused-pane preview pane on macOS 14/15. PDFView
/// owns its own scroll view, paginates natively, and respects
/// trackpad / scroll-wheel input out of the box.
struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}

/// Plain `.compact` `QLPreviewView` — fit-to-bounds (preserves aspect
/// ratio, can letterbox on the sides for portrait pages in a wide
/// pane) but it's the only embed shape that keeps formats *without*
/// a system QL generator (HWP/HWPX) showing their system-fallback
/// preview at all. We tried two more aggressive shapes and reverted:
///
///   - `.normal` (no wrap) → renders office docs at natural pixel
///     size, crops mid-paragraph in a half-width pane.
///   - `.normal` inside an NSScrollView with `autoresizingMask =
///     .width` → fixes DOCX width-fit but collapses HWP to a 0-height
///     blank because its intrinsic content size is unknown.
///
/// `.compact` accepts the DOCX letterbox in exchange for HWP working
/// and behaves consistently for every other format the system has a
/// generator for. Multi-page navigation lives on ⎵ (floating
/// QLPreviewPanel). PDFs route to `PDFPreview` separately.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? URL) != url {
            nsView.previewItem = url as NSURL
        }
    }
}
