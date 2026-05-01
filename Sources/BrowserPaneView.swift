import AppKit
import SwiftUI

struct BrowserPaneView: View {
    let index: Int
    @ObservedObject var viewModel: FolderBrowserViewModel
    let isFocused: Bool
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            Divider()
            columnHeader
            Divider()
            content
            Divider()
            statusBar
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 0)
                .stroke(isFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isFocused ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus()
        }
    }

    private var paneHeader: some View {
        HStack(spacing: 6) {
            Text("Pane \(index + 1)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isFocused ? .primary : .secondary)

            Text(viewModel.folderURL?.lastPathComponent ?? "No Folder")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                viewModel.chooseFolder()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open Folder in Pane \(index + 1)")

            Button {
                viewModel.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload Pane \(index + 1)")
            .disabled(viewModel.folderURL == nil)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(.bar)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            SortHeaderButton(
                title: "Name",
                key: .name,
                currentKey: viewModel.sortKey,
                ascending: viewModel.sortAscending
            ) {
                viewModel.setSort(.name)
            }
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

            SortHeaderButton(
                title: "Modified",
                key: .modified,
                currentKey: viewModel.sortKey,
                ascending: viewModel.sortAscending
            ) {
                viewModel.setSort(.modified)
            }
            .frame(width: 112, alignment: .leading)

            SortHeaderButton(
                title: "Size",
                key: .size,
                currentKey: viewModel.sortKey,
                ascending: viewModel.sortAscending
            ) {
                viewModel.setSort(.size)
            }
            .frame(width: 70, alignment: .trailing)

            SortHeaderButton(
                title: "Kind",
                key: .kind,
                currentKey: viewModel.sortKey,
                ascending: viewModel.sortAscending
            ) {
                viewModel.setSort(.kind)
            }
            .frame(width: 96, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.folderURL == nil {
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)

                Text("Open a folder")
                    .font(.headline)

                Button("Open Folder...") {
                    viewModel.chooseFolder()
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)

                Text("Could not open folder")
                    .font(.headline)

                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    viewModel.reload()
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            List(selection: $viewModel.selection) {
                ForEach(viewModel.entries) { entry in
                    FileEntryRow(entry: entry)
                        .tag(entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            viewModel.open(entry)
                        }
                        .contextMenu {
                            Button("Open") {
                                viewModel.open(entry)
                            }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                            }
                        }
                }
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.large)
                } else if viewModel.entries.isEmpty {
                    Text("No items")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            if viewModel.isLoading {
                Text("Loading...")
            } else {
                Text("\(viewModel.entries.count) item\(viewModel.entries.count == 1 ? "" : "s")")
            }

            if let selectedEntry = viewModel.selectedEntry {
                Text("-")
                    .foregroundStyle(.tertiary)
                Text(selectedEntry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if viewModel.includeHidden {
                Text("Hidden")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(.bar)
    }
}

private struct SortHeaderButton: View {
    let title: String
    let key: FileEntrySortKey
    let currentKey: FileEntrySortKey
    let ascending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if currentKey == key {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    private var alignment: Alignment {
        key == .size ? .trailing : .leading
    }
}

private struct FileEntryRow: View {
    let entry: FileEntry

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                    .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                    .frame(width: 18)

                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

            Text(Self.modifiedDateFormatter.string(from: entry.modificationDate))
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)

            Text(Self.sizeFormatter.string(fromByteCount: entry.size))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            Text(entry.kind)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 96, alignment: .leading)
        }
        .font(.system(size: 13))
        .padding(.vertical, 1)
    }

    private static let modifiedDateFormatter = ModifiedDateFormatter()
    private static let sizeFormatter = FileSizeFormatter()
}

private struct ModifiedDateFormatter {
    private let formatter: DateFormatter

    init() {
        formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
    }

    func string(from date: Date?) -> String {
        guard let date else {
            return "--"
        }

        return formatter.string(from: date)
    }
}

private struct FileSizeFormatter {
    private let formatter: ByteCountFormatter

    init() {
        formatter = ByteCountFormatter()
        formatter.countStyle = .file
    }

    func string(fromByteCount size: Int64?) -> String {
        guard let size else {
            return "--"
        }

        return formatter.string(fromByteCount: size)
    }
}

