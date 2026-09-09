import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var viewModel: SidebarViewModel
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var repoCallout: RepoCalloutController
    @ObservedObject var integrations: IntegrationsSidebarModel
    @Binding var selectedURL: URL?
    /// Distinct Finder tags observed in the focused tab's current
    /// listing. Empty when the focused folder has no tagged items.
    /// MainWindowView recomputes this on every focused-tab change so
    /// the sidebar always mirrors what's visible in the active pane.
    let tagsSummary: [TagSummary]
    /// Tap handler for a sidebar tag row. The owning view typically
    /// pushes the name into the focused tab's `searchQuery` so the
    /// list filters down to matching items.
    let onTagSelected: (String) -> Void
    let onSelect: (URL) -> Void

    /// Custom drag-payload identifier for project rows. Distinct from the
    /// favorite reorder type so dragging a project onto a favorite (or
    /// vice versa) is silently ignored instead of firing the wrong move.
    static let projectDragType = "com.mqdir.project.uuid"

    /// Whichever favorite is currently being inline-renamed. Cleared on
    /// commit (Enter) or cancel (Esc / focus loss with empty input).
    @State private var editingFavoriteID: Favorite.ID?
    /// Working draft for the rename TextField. Mirrored to a focus
    /// state so we can autoselect on entry.
    @State private var editingFavoriteDraft: String = ""
    @FocusState private var renameFavoriteFocused: Favorite.ID?

    /// Same idea for the Projects section, kept on a separate state slot
    /// so editing a project name doesn't leak into a favorite editor.
    @State private var editingProjectID: UUID?
    @State private var editingProjectDraft: String = ""
    @FocusState private var renameProjectFocused: UUID?

    /// Drop highlights for favorites — section vs row, mutually exclusive.
    @State private var favSectionDropTargeted = false
    @State private var favRowDropTargetedID: Favorite.ID?
    /// Drop highlight for project reorder.
    @State private var projectRowDropTargetedID: UUID?
    /// Project being dragged for reorder.
    @State private var draggingProjectID: UUID?

    @State private var showingFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    favoritesSection
                        .padding(.bottom, 8)

                    tagsSection
                        .padding(.bottom, 8)

                    projectsSection

                    integrationSection
                        .padding(.top, 8)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            sidebarFooter
        }
        .background(Theme.Color.sidebarBg)
        .sheet(isPresented: $showingFeedback) {
            FeedbackSheet(repoCallout: repoCallout)
        }
    }

    /// Bottom row: a help menu (always visible) and an update pill that
    /// only appears when Sparkle's background check has flagged a new
    /// version. The pill is loud on purpose — the previous flat bar was
    /// quiet enough that users missed available updates.
    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            helpMenu
            if updateManager.updateAvailable {
                updatePill
            }
            if repoCallout.shouldShowPill {
                repoPill
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Color.separator).frame(height: 0.5)
        }
    }

    private var helpMenu: some View {
        Menu {
            Button("Welcome to mq-dir") { openURL("https://mqdir.com") }
            Button("Send Feedback") { showingFeedback = true }
            Button("⭐ Star on GitHub") {
                repoCallout.openRepo()
            }
            Divider()
            Button("Check for Updates") {
                updateManager.checkForUpdatesAndShowUI()
            }
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.Color.label.opacity(0.55))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Help")
    }

    private var updatePill: some View {
        Button {
            updateManager.checkForUpdatesAndShowUI()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(pillLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Theme.Color.accent)
            )
        }
        .buttonStyle(.plain)
        .help("Install the available update")
    }

    private var pillLabel: String {
        if let version = updateManager.availableVersion {
            return "Update Available: \(version)"
        }
        return "Update Available"
    }

    /// Repo callout. Mirrors `updatePill`'s capsule style with a yellow
    /// tint so the two pills read as a related but distinct "quiet CTA"
    /// family. Right-click is the explicit anti-nag escape hatch —
    /// once dismissed, never returns.
    private var repoPill: some View {
        Button {
            repoCallout.openRepo()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Star mq-dir")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.yellow)
            )
        }
        .buttonStyle(.plain)
        .help("Open the mq-dir GitHub repo")
        .contextMenu {
            Button("Don't show this again") {
                repoCallout.dismissPermanently()
            }
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Favorites

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Favorites")

            if viewModel.favorites.isEmpty {
                emptyFavoritesHint
            } else {
                ForEach(viewModel.favorites) { favorite in
                    favoriteRow(favorite)
                }
            }
        }
        // Whole-section drop zone so users can drop a folder anywhere in
        // the Favorites area (not just on an existing row) to append.
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(favSectionDropTargeted ? Theme.Color.accent.opacity(0.10) : .clear)
                .padding(.horizontal, 6)
        )
        .onDrop(
            of: DragDropSupport.acceptedDropTypes,
            isTargeted: $favSectionDropTargeted
        ) { providers in
            handleDrop(providers: providers, before: nil)
            return true
        }
    }

    private var emptyFavoritesHint: some View {
        Text("Drag folders here to add")
            .font(.system(size: 10))
            .foregroundStyle(Theme.Color.labelTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tags (read-only view of Finder tags in the focused tab)

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Tags")
            if tagsSummary.isEmpty {
                Text("No tags in this folder")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.labelTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(tagsSummary) { summary in
                    tagRow(summary)
                }
            }
        }
    }

    private func tagRow(_ summary: TagSummary) -> some View {
        Button {
            onTagSelected(summary.name)
        } label: {
            HStack(spacing: 8) {
                if let color = TagColor.color(forLabel: summary.labelNumber) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .strokeBorder(Theme.Color.labelTertiary, lineWidth: 1)
                        .frame(width: 8, height: 8)
                }
                Text(summary.name)
                    .font(Theme.Font.sidebarItem)
                    .foregroundStyle(Theme.Color.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Filter the focused tab by \u{201C}\(summary.name)\u{201D}")
    }

    @ViewBuilder
    private func favoriteRow(_ favorite: Favorite) -> some View {
        let resolved = viewModel.resolveURL(favorite)
        let isActive = resolved != nil && selectedURL == resolved
        let isStale = resolved == nil
        let isEditing = editingFavoriteID == favorite.id
        let isDropTarget = favRowDropTargetedID == favorite.id

        let row = HStack(spacing: 6) {
            iconView(for: resolved)
                .frame(width: 14)
                .opacity(isStale ? 0.4 : 1)
            if isEditing {
                TextField("", text: $editingFavoriteDraft)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.sidebarItem)
                    .foregroundStyle(Theme.Color.label)
                    .focused($renameFavoriteFocused, equals: favorite.id)
                    .onSubmit { commitRename(favorite.id) }
                    .onKeyPress(.escape) {
                        cancelRename()
                        return .handled
                    }
            } else {
                Text(favorite.label)
                    .font(Theme.Font.sidebarItem)
                    .foregroundStyle(isStale ? Theme.Color.labelTertiary : Theme.Color.label)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, isActive ? 10 : 14)
        .padding(.trailing, 8)
        .frame(height: 22)
        .background(rowBackground(isActive: isActive, isDropTarget: isDropTarget))
        .overlay(alignment: .top) {
            // Insertion indicator when reordering / dropping a folder
            // before this row. The bar visually replaces the section
            // highlight while a row-level drop is active.
            if isDropTarget {
                Rectangle()
                    .fill(Theme.Color.accent)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }
        }
        .contentShape(Rectangle())
        .help(isStale ? (favorite.fallbackPath ?? "Folder unavailable") : (resolved?.path ?? favorite.label))
        .onTapGesture {
            guard !isEditing else { return }
            if let url = resolved {
                selectedURL = url
                onSelect(url)
            }
        }
        .contextMenu {
            Button("Rename") { startRename(favorite) }
                .disabled(isStale)
            Button("Remove from Sidebar", role: .destructive) {
                viewModel.remove(favorite.id)
            }
        }

        // Row is both a drag SOURCE (reorder) and a drop TARGET (reorder
        // OR external folder add at this insertion point).
        row
            .onDrag {
                NSItemProvider(
                    object: favorite.id.uuidString as NSString
                )
            }
            .onDrop(
                of: DragDropSupport.acceptedDropTypes + [UTType.plainText.identifier],
                isTargeted: Binding(
                    get: { favRowDropTargetedID == favorite.id },
                    set: { favRowDropTargetedID = $0 ? favorite.id : nil }
                )
            ) { providers in
                handleDrop(providers: providers, before: favorite.id)
                return true
            }
    }

    private func iconView(for url: URL?) -> some View {
        Group {
            if let url {
                // NSWorkspace returns the actual Finder icon (custom icon,
                // tag color, sync overlay). Falls back to the generic
                // folder symbol when something goes wrong.
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.labelTertiary)
            }
        }
    }

    private func rowBackground(isActive: Bool, isDropTarget: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isActive ? Color.white.opacity(0.06) : Color.clear)
            .padding(.horizontal, isActive ? 6 : 0)
    }

    // MARK: Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("PROJECTS")
                    .font(Theme.Font.sidebarHeader)
                    .tracking(0.5)
                    .foregroundStyle(Theme.Color.labelTertiary)
                Spacer(minLength: 0)
                Button {
                    workspace.createProject()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.Color.labelSecondary)
                        .frame(width: 16, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Project")
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)

            ForEach(workspace.workspace.projects) { project in
                projectRow(project)
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        let isActive = workspace.workspace.activeProjectID == project.id
        let isEditing = editingProjectID == project.id
        let isDropTarget = projectRowDropTargetedID == project.id
        let isOnlyProject = workspace.workspace.projects.count == 1

        let row = HStack(spacing: 6) {
            Image(systemName: "folder.fill.badge.gearshape")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Theme.Color.accent.opacity(0.85) : Color(white: 0.55))
                .frame(width: 14)
            if isEditing {
                TextField("", text: $editingProjectDraft)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.sidebarItem)
                    .foregroundStyle(Theme.Color.label)
                    .focused($renameProjectFocused, equals: project.id)
                    .onSubmit { commitProjectRename(project.id) }
                    .onKeyPress(.escape) {
                        cancelProjectRename()
                        return .handled
                    }
            } else {
                Text(project.name)
                    .font(Theme.Font.sidebarItem)
                    .foregroundStyle(isActive ? Theme.Color.label : Theme.Color.labelSecondary)
                    .lineLimit(1)
            }
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
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(Theme.Color.accent)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditing else { return }
            workspace.switchTo(projectID: project.id)
        }
        .contextMenu {
            Button("Rename") { startProjectRename(project) }
            Button("Duplicate Project") { workspace.duplicateProject(project.id) }
            Button("Delete", role: .destructive) {
                workspace.delete(project.id)
            }
            // Last-project guard. The manager refuses too, but disabling
            // the menu item makes the intent visible up-front.
            .disabled(isOnlyProject)
        }

        row
            .onDrag {
                draggingProjectID = project.id
                return makeProjectDragProvider(project.id)
            }
            .onDrop(
                of: [Self.projectDragType],
                delegate: ProjectReorderDropDelegate(
                    target: project.id,
                    workspace: workspace,
                    draggingID: $draggingProjectID,
                    highlightID: $projectRowDropTargetedID
                )
            )
    }

    /// Build an item provider whose payload is the project UUID under
    /// our private type identifier. Using a custom type (instead of plain
    /// text) keeps a project drag from accidentally triggering the
    /// favorite-reorder drop target during a sloppy mouse path.
    private func makeProjectDragProvider(_ id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: Self.projectDragType,
            visibility: .ownProcess
        ) { completion in
            completion(Data(id.uuidString.utf8), nil)
            return nil
        }
        return provider
    }

    // MARK: Coding app integrations

    private var integrationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                IntegrationAppPicker(selection: $integrations.provider)
                integrationSyncChip
            }
            .padding(.horizontal, 12)
            Text(integrations.provider.sourceDescription)
                .font(.system(size: 9))
                .foregroundStyle(Theme.Color.labelTertiary)
                .padding(.horizontal, 14)
            if let error = integrations.lastError {
                Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 14)
            }
            if integrations.workspaces.isEmpty {
                Text(integrationEmptyStateMessage).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
            } else {
                ForEach(integrations.workspaces) { integrationRow($0) }
            }
            if let app = WorkspaceIntegrationClient.applicationURL(for: integrations.provider) {
                Button("Open \(integrations.provider.title)") { NSWorkspace.shared.open(app) }
                    .font(.caption).padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 8)
    }

    /// Pill-shaped Sync button. Higher hit-target + label than the bare
    /// refresh icon — easier to find for someone who's never used the
    /// integration before. Swaps to "Syncing…" with a spinner while a
    /// fetch is in flight, and disables to prevent double-taps.
    private var integrationSyncChip: some View {
        Button {
            Task { await integrations.sync() }
        } label: {
            HStack(spacing: 4) {
                if integrations.isSyncing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                        .frame(width: 8, height: 8)
                }
                Text(integrations.isSyncing ? "Syncing\u{2026}" : "Sync")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Theme.Color.label)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.white.opacity(integrations.isSyncing ? 0.04 : 0.10))
            )
            .overlay(
                Capsule().strokeBorder(Theme.Color.separator, lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(integrations.isSyncing)
        .help("Sync \(integrations.provider.title) workspaces")
    }

    /// Picks the right one-liner for an empty workspaces list. Three
    /// distinct states the previous version collapsed to one message:
    /// (1) sync errored, (2) sync ran but cmux genuinely has no
    /// workspaces, (3) we haven't synced yet.
    private var integrationEmptyStateMessage: String {
        if integrations.lastError != nil { return "Check the selected app, then retry Sync." }
        if integrations.lastSyncDate != nil { return "No local workspaces found." }
        return "Press Sync to load workspaces."
    }

    private func integrationRow(_ ws: IntegrationWorkspace) -> some View {
        let cwd: URL? = FileManager.default.fileExists(atPath: ws.currentDirectory) ? URL(fileURLWithPath: ws.currentDirectory) : nil
        let isActive = cwd != nil && selectedURL == cwd

        return Button {
            guard let url = cwd else { return }
            // ⌘-click → open in a new tab in the focused pane (matches
            // the Finder convention used by tree-view ⌘-click).
            // Plain click → swap the focused pane's active tab to it.
            if NSEvent.modifierFlags.contains(.command) {
                AppCommand.openURLInNewTab(url: url).post()
            } else {
                selectedURL = url
                onSelect(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: ws.selected ? "play.circle.fill" : "terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(ws.selected
                                     ? Theme.Color.accent.opacity(0.85)
                                     : Color(white: 0.55))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(ws.title)
                        .font(Theme.Font.sidebarItem)
                        .foregroundStyle(Theme.Color.label)
                        .lineLimit(1)
                    if let cwd {
                        Text(cwd.lastPathComponent)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Color.labelTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, isActive ? 10 : 14)
            .padding(.trailing, 8)
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.white.opacity(0.06) : Color.clear)
                    .padding(.horizontal, isActive ? 6 : 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(cwd == nil)
        .help(cwd == nil ? "Unavailable on this Mac: " + ws.currentDirectory : ws.currentDirectory)
    }

    // MARK: Section chrome

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.Font.sidebarHeader)
            .tracking(0.5)
            .foregroundStyle(Theme.Color.labelTertiary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    // MARK: Rename flow

    private func startRename(_ favorite: Favorite) {
        editingFavoriteID = favorite.id
        editingFavoriteDraft = favorite.label
        DispatchQueue.main.async { renameFavoriteFocused = favorite.id }
    }

    private func commitRename(_ id: Favorite.ID) {
        viewModel.rename(id, to: editingFavoriteDraft)
        cancelRename()
    }

    private func cancelRename() {
        editingFavoriteID = nil
        editingFavoriteDraft = ""
        renameFavoriteFocused = nil
    }

    private func startProjectRename(_ project: Project) {
        editingProjectID = project.id
        editingProjectDraft = project.name
        DispatchQueue.main.async { renameProjectFocused = project.id }
    }

    private func commitProjectRename(_ id: UUID) {
        workspace.rename(id, to: editingProjectDraft)
        cancelProjectRename()
    }

    private func cancelProjectRename() {
        editingProjectID = nil
        editingProjectDraft = ""
        renameProjectFocused = nil
    }

    // MARK: Drop dispatch

    /// Routes incoming drops. Resolves URLs first so tab drags (which
    /// carry both a `.ownProcess` plain-text id *and* a file-URL) land
    /// on the add-favorite path; the UUID-string fallback only fires
    /// when no URL is present, which keeps favorite-row reorder
    /// working. The previous order checked plain-text first and would
    /// silently swallow tab drops because `UUID(uuidString:)` rejected
    /// the `ObjectIdentifier(0x…)` literal.
    private func handleDrop(providers: [NSItemProvider], before targetID: Favorite.ID?) {
        Task {
            let urls = await DragDropSupport.resolveURLs(from: providers)
            if !urls.isEmpty {
                await MainActor.run {
                    // Add each dropped URL, capturing the ID of every
                    // favorite that's genuinely new (`add` no-ops on
                    // files/dupes, so we diff against the prior set
                    // rather than assuming `favorites.last` is ours).
                    var addedIDs: [Favorite.ID] = []
                    for url in urls {
                        let before = Set(viewModel.favorites.map(\.id))
                        viewModel.add(url: url)
                        if let new = viewModel.favorites.first(where: { !before.contains($0.id) }) {
                            addedIDs.append(new.id)
                        }
                    }
                    // Move the whole batch as a contiguous block before
                    // the target, preserving drop order — dropping 3
                    // folders lands all 3 at the drop point, not just
                    // the last. Moving in forward order works because
                    // each `move(before: targetID)` inserts immediately
                    // before the target, after the previously-moved
                    // item, so the block ends up as [first … last] right
                    // before the target row.
                    if let targetID {
                        for id in addedIDs where id != targetID {
                            viewModel.move(sourceID: id, before: targetID)
                        }
                    }
                    // No-op when the drop didn't originate from a tab;
                    // when it did, clearing here flips
                    // `BrowserPaneView`'s opacity overlay back on so
                    // the source tab stops looking disabled.
                    TabDragCoordinator.shared.clear()
                }
                return
            }
            // No URLs — fall back to favorite reorder via UUID payload.
            if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
                provider.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let str = obj as? String,
                          let uuid = UUID(uuidString: str)
                    else { return }
                    Task { @MainActor in
                        viewModel.move(sourceID: uuid, before: targetID)
                    }
                }
            }
        }
    }
}

// MARK: Project reorder

/// Project equivalent of the tab reorder delegate. Hovering a sibling row
/// only previews the landing spot (the blue insertion bar driven by
/// `highlightID`); the actual `workspace.move` runs ONCE in `performDrop`.
///
/// The previous version mutated the model in `dropEntered` on every
/// hover-cross, which armed a debounced save per crossing and — when the
/// *active* project moved — re-keyed `MainWindowView` mid-drag (the app
/// keys the window on `activeProjectID`). Deferring the commit to mouse-up
/// mirrors `TabReorderDropDelegate` and keeps the drag visually stable.
private struct ProjectReorderDropDelegate: DropDelegate {
    let target: UUID
    @ObservedObject var workspace: WorkspaceManager
    @Binding var draggingID: UUID?
    @Binding var highlightID: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingID, dragging != target else { return }
        // Preview only — show where the row will land, don't move it yet.
        highlightID = target
    }

    func dropExited(info: DropInfo) {
        if highlightID == target { highlightID = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingID = nil
            highlightID = nil
        }
        guard let dragging = draggingID, dragging != target else { return false }
        // Insert AFTER the target if dragging from earlier in the list,
        // BEFORE if dragging from later — same convention as favorites.
        let projects = workspace.workspace.projects
        guard let from = projects.firstIndex(where: { $0.id == dragging }),
              let to = projects.firstIndex(where: { $0.id == target })
        else { return false }
        let beforeID: UUID? = from < to
            ? (to + 1 < projects.count ? projects[to + 1].id : nil)
            : projects[to].id
        workspace.move(sourceID: dragging, before: beforeID)
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

/// Compact app switcher; native menu behavior and keyboard navigation are preserved.
private struct IntegrationAppPicker: View {
    @Binding var selection: WorkspaceProvider
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(WorkspaceProvider.allCases) { provider in
                Button {
                    selection = provider
                } label: {
                    HStack {
                        Text(provider.title)
                        if provider == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                appIcon
                    .frame(width: 16, height: 16)
                Text(selection.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 3)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.Color.labelSecondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0.045))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.Color.separator.opacity(isHovered ? 0.8 : 0.5), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { isHovered = $0 }
        .help("Choose integration app — " + selection.title)
        .accessibilityLabel("Integration app")
        .accessibilityValue(selection.title)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let url = WorkspaceIntegrationClient.applicationURL(for: selection) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: selection == .cmux || selection == .paseo ? "terminal" : "app.dashed")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Color.labelSecondary)
        }
    }
}
