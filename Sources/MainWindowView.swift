import SwiftUI

struct MainWindowView: View {
    @StateObject private var viewModel = FolderBrowserViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            columnHeader
            Divider()
            content
            Divider()
            statusBar
        }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirOpenFolderRequested)) { _ in
            viewModel.chooseFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirOpenSelectedRequested)) { _ in
            viewModel.openSelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirRevealSelectedRequested)) { _ in
            viewModel.revealSelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirReloadRequested)) { _ in
            viewModel.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirParentFolderRequested)) { _ in
            viewModel.openParentFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirToggleHiddenFilesRequested)) { _ in
            viewModel.toggleHiddenFiles()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.chooseFolder()
            } label: {
                Label("Open Folder", systemImage: "folder")
            }

            Button {
                viewModel.openParentFolder()
            } label: {
                Image(systemName: "chevron.up")
            }
            .help("Parent Folder")
            .disabled(viewModel.folderURL == nil)

            Button {
                viewModel.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload")
            .disabled(viewModel.folderURL == nil)

            Text(viewModel.folderDisplayPath)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Toggle(isOn: Binding(
                get: { viewModel.includeHidden },
                set: { viewModel.includeHidden = $0 }
            )) {
                Text("Hidden")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Button {
                viewModel.revealSelected()
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .help("Reveal in Finder")
            .disabled(viewModel.selectedEntry == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
            .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)

            SortHeaderButton(
                title: "Date Modified",
                key: .modified,
                currentKey: viewModel.sortKey,
                ascending: viewModel.sortAscending
            ) {
                viewModel.setSort(.modified)
            }
            .frame(width: 160, alignment: .leading)

            SortHeaderButton(
                title: "Size",
                key: .size,
                currentKey: viewModel.sortKey,
                ascending: viewModel.sortAscending
            ) {
                viewModel.setSort(.size)
            }
            .frame(width: 96, alignment: .trailing)

            SortHeaderButton(
                title: "Kind",
                key: .kind,
                currentKey: viewModel.sortKey,
                ascending: viewModel.sortAscending
            ) {
                viewModel.setSort(.kind)
            }
            .frame(width: 150, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.folderURL == nil {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)

                Text("Open a folder to browse")
                    .font(.title2)
                    .fontWeight(.medium)

                Button("Open Folder...") {
                    viewModel.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                Text("Could not open folder")
                    .font(.headline)

                Text(errorMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    viewModel.reload()
                }
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
        HStack(spacing: 8) {
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

            Text(viewModel.includeHidden ? "Hidden files shown" : "Hidden files hidden")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
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
            .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)

            Text(Self.modifiedDateFormatter.string(from: entry.modificationDate))
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)

            Text(Self.sizeFormatter.string(fromByteCount: entry.size))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .trailing)

            Text(entry.kind)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 150, alignment: .leading)
        }
        .font(.system(size: 13))
        .padding(.vertical, 1)
    }

    private static let modifiedDateFormatter = ModifiedDateFormatter()
    private static let sizeFormatter = FileSizeFormatter()
}

#Preview {
    MainWindowView()
}

private struct ModifiedDateFormatter {
    private let formatter: DateFormatter

    init() {
        formatter = DateFormatter()
        formatter.dateStyle = .medium
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
