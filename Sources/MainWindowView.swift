import SwiftUI

struct MainWindowView: View {
    @StateObject private var pane0 = FolderBrowserViewModel()
    @StateObject private var pane1 = FolderBrowserViewModel()
    @StateObject private var pane2 = FolderBrowserViewModel()
    @StateObject private var pane3 = FolderBrowserViewModel()

    @State private var layout: PaneLayout = .four
    @State private var focusedPaneIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            paneGrid
        }
        .onChange(of: layout) { _, newLayout in
            if focusedPaneIndex >= newLayout.count {
                focusedPaneIndex = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirOpenFolderRequested)) { _ in
            focusedPane.chooseFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirOpenSelectedRequested)) { _ in
            focusedPane.openSelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirRevealSelectedRequested)) { _ in
            focusedPane.revealSelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirReloadRequested)) { _ in
            focusedPane.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirParentFolderRequested)) { _ in
            focusedPane.openParentFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mqdirToggleHiddenFilesRequested)) { _ in
            focusedPane.toggleHiddenFiles()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                focusedPane.chooseFolder()
            } label: {
                Label("Open Folder", systemImage: "folder")
            }

            Button {
                focusedPane.openParentFolder()
            } label: {
                Image(systemName: "chevron.up")
            }
            .help("Parent Folder")
            .disabled(focusedPane.folderURL == nil)

            Button {
                focusedPane.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload")
            .disabled(focusedPane.folderURL == nil)

            Text(focusedPane.folderDisplayPath)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Toggle(isOn: Binding(
                get: { focusedPane.includeHidden },
                set: { focusedPane.includeHidden = $0 }
            )) {
                Text("Hidden")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Button {
                focusedPane.revealSelected()
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .help("Reveal in Finder")
            .disabled(focusedPane.selectedEntry == nil)

            Picker("Layout", selection: $layout) {
                ForEach(PaneLayout.allCases) { paneLayout in
                    Text(paneLayout.label).tag(paneLayout)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var paneGrid: some View {
        switch layout {
        case .one:
            paneView(0)
        case .two:
            HStack(spacing: 0) {
                paneView(0)
                Divider()
                paneView(1)
            }
        case .four:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    paneView(0)
                    Divider()
                    paneView(1)
                }
                Divider()
                HStack(spacing: 0) {
                    paneView(2)
                    Divider()
                    paneView(3)
                }
            }
        }
    }

    private func paneView(_ index: Int) -> some View {
        BrowserPaneView(
            index: index,
            viewModel: pane(at: index),
            isFocused: focusedPaneIndex == index
        ) {
            focusedPaneIndex = index
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var focusedPane: FolderBrowserViewModel {
        pane(at: focusedPaneIndex)
    }

    private func pane(at index: Int) -> FolderBrowserViewModel {
        switch index {
        case 0:
            pane0
        case 1:
            pane1
        case 2:
            pane2
        default:
            pane3
        }
    }
}

private enum PaneLayout: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case four = 4

    var id: Int {
        rawValue
    }

    var count: Int {
        rawValue
    }

    var label: String {
        "\(rawValue)"
    }
}

#Preview {
    MainWindowView()
}
