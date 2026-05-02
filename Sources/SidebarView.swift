import SwiftUI

struct SidebarView: View {
    @Binding var selectedURL: URL?
    let onSelect: (URL) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section("Favorites") {
                    ForEach(SidebarItem.favorites) { item in
                        sidebarRow(item, icon: "folder.fill", iconColor: Theme.Color.accent.opacity(0.85))
                    }
                }
                .padding(.bottom, 8)

                section("Locations") {
                    ForEach(SidebarItem.locations) { item in
                        sidebarRow(item, icon: "internaldrive.fill", iconColor: Color(white: 0.55))
                    }
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Color.sidebarBg)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(Theme.Font.sidebarHeader)
                .tracking(0.5)
                .foregroundStyle(Theme.Color.labelTertiary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)
            content()
        }
    }

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem, icon: String, iconColor: Color) -> some View {
        let isActive = selectedURL == item.url

        Button {
            selectedURL = item.url
            onSelect(item.url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
                    .frame(width: 14)
                Text(item.label)
                    .font(Theme.Font.sidebarItem)
                    .foregroundStyle(Theme.Color.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, isActive ? 10 : 14)
            .padding(.trailing, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.white.opacity(0.06) : Color.clear)
                    .padding(.horizontal, isActive ? 6 : 0)
            )
        }
        .buttonStyle(.plain)
    }

}

private struct SidebarItem: Identifiable {
    let id = UUID()
    let label: String
    let url: URL

    init(_ label: String, _ url: URL) {
        self.label = label
        self.url = url
    }

    static var favorites: [SidebarItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            SidebarItem("Desktop",   home.appendingPathComponent("Desktop")),
            SidebarItem("Documents", home.appendingPathComponent("Documents")),
            SidebarItem("Downloads", home.appendingPathComponent("Downloads")),
            SidebarItem("Pictures",  home.appendingPathComponent("Pictures")),
            SidebarItem("Movies",    home.appendingPathComponent("Movies")),
            SidebarItem("Music",     home.appendingPathComponent("Music")),
        ]
    }

    static var locations: [SidebarItem] {
        [
            SidebarItem("Macintosh HD", URL(fileURLWithPath: "/")),
            SidebarItem("Applications", URL(fileURLWithPath: "/Applications")),
        ]
    }
}
