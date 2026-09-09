import SwiftUI

struct SearchOptionsMenu: View {
    @ObservedObject var model: FolderBrowserViewModel
    @ObservedObject var workspace: WorkspaceManager
    let projectRoots: [URL]
    @State private var saving = false
    @State private var name = ""

    var body: some View {
        Menu {
            Picker("File type", selection: $model.searchFilter.category) {
                ForEach(FileSearchCategory.allCases, id: \.self) { category in
                    Text(category.title).tag(category)
                }
            }
            Picker("Modified", selection: Binding(
                get: { model.searchFilter.modifiedWithinDays ?? 0 },
                set: { model.searchFilter.modifiedWithinDays = $0 == 0 ? nil : $0 }
            )) {
                Text("Any time").tag(0)
                Text("Last 24 hours").tag(1)
                Text("Last 7 days").tag(7)
                Text("Last 30 days").tag(30)
            }
            Toggle("Files only", isOn: $model.searchFilter.filesOnly)
            Divider()
            Button("Recent project files") {
                model.applySearch(SavedFileSearch(name: "Recent project files", query: "",
                    filter: FileSearchFilter(modifiedWithinDays: 7, filesOnly: true), projectScope: true), projectRoots: projectRoots)
            }
            .disabled(projectRoots.isEmpty)
            Button("Save current search…") {
                name = model.searchQuery.isEmpty ? "Recent files" : model.searchQuery
                saving = true
            }
            .disabled(!model.isFiltering)
            if !workspace.workspace.settings.savedSearches.isEmpty {
                Menu("Saved searches") {
                    ForEach(workspace.workspace.settings.savedSearches) { search in
                        Menu(search.name) {
                            Button("Apply") { model.applySearch(search, projectRoots: projectRoots) }
                            Button("Remove", role: .destructive) { workspace.removeSearch(search.id) }
                        }
                    }
                }
            }
            Button("Clear filters") { model.clearSearch() }
        } label: {
            Image(systemName: model.searchFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help("Search filters and saved searches")
        .accessibilityLabel("Search filters")
        .alert("Save search", isPresented: $saving) {
            TextField("Name", text: $name)
            Button("Save") {
                workspace.saveSearch(SavedFileSearch(name: name.trimmingCharacters(in: .whitespaces),
                    query: model.searchQuery, filter: model.searchFilter, projectScope: model.projectSearchRoots != nil))
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
    }
}
