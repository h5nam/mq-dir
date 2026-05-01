import SwiftUI

struct MainWindowView: View {
    @State private var sidebarSelection: String? = "skeleton"

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Section("Sidebar (M4)") {
                    Text("Folder tree lands in M4")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            VStack(spacing: 12) {
                Text("mq-dir — M0 skeleton")
                    .font(.title2)
                    .fontWeight(.medium)
                Text("Folder browsing lands in M1.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    MainWindowView()
}
