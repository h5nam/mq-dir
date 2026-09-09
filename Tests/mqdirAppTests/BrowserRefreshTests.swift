import Combine
import XCTest

final class BrowserRefreshTests: XCTestCase {
    @MainActor
    func testReloadRefreshesRecursiveSearchAfterExternalChange() async throws {
        try await withBrowser { root, model in
            let sub = root.appendingPathComponent("sub")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
            let old = sub.appendingPathComponent("target-old.txt")
            try Data().write(to: old)
            model.searchQuery = "target"
            try await self.waitFor { !model.isSearching }
            XCTAssertEqual(model.visibleEntries.map(\.name), ["target-old.txt"])
            try FileManager.default.removeItem(at: old)
            try Data().write(to: sub.appendingPathComponent("target-new.txt"))
            model.reload()
            try await self.waitFor { !model.isLoading && !model.isSearching }
            XCTAssertEqual(model.visibleEntries.map(\.name), ["target-new.txt"])
        }
    }

    @MainActor
    func testHiddenToggleRefreshesExistingQuery() async throws {
        try await withBrowser { root, model in
            try Data().write(to: root.appendingPathComponent(".target-hidden.txt"))
            model.searchQuery = "target"
            try await self.waitFor { !model.isSearching }
            XCTAssertTrue(model.visibleEntries.isEmpty)
            model.includeHidden = true
            try await self.waitFor { !model.isLoading && !model.isSearching }
            XCTAssertEqual(model.visibleEntries.map(\.name), [".target-hidden.txt"])
        }
    }

    @MainActor
    func testSlowTreeLoadRunsOffMainAndCannotRepopulateCollapsedFolder() async throws {
        let started = expectation(description: "child load started")
        let finished = expectation(description: "child load finished")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let loader: FolderBrowserViewModel.DirectoryLoader = { url, hidden, cancelled in
            if url.lastPathComponent == "slow" {
                XCTAssertFalse(Thread.isMainThread)
                started.fulfill()
                _ = release.wait(timeout: .now() + 3)
                defer { finished.fulfill() }
                // Deliberately ignore cancellation to verify the result guard.
                return try FileSystemService().enumerateDirectory(at: url)
            }
            return try FileSystemService().enumerateDirectory(at: url, includingHidden: hidden, isCancelled: cancelled)
        }
        try await withBrowser(directoryLoader: loader) { root, model in
            let slow = root.appendingPathComponent("slow")
            try FileManager.default.createDirectory(at: slow, withIntermediateDirectories: false)
            try Data().write(to: slow.appendingPathComponent("child.txt"))
            let stale = self.expectation(description: "collapsed folder must not reappear")
            stale.isInverted = true
            let subscription = model.$treeChildren.sink { children in
                if children[slow.path] != nil { stale.fulfill() }
            }
            model.toggleExpanded(slow)
            await self.fulfillment(of: [started], timeout: 2)
            model.toggleExpanded(slow)
            release.signal()
            await self.fulfillment(of: [finished], timeout: 2)
            await self.fulfillment(of: [stale], timeout: 0.1)
            XCTAssertNil(model.treeChildren[slow.path])
            withExtendedLifetime(subscription) {}
        }
    }

    @MainActor
    func testDeepRevealWaitsUntilAncestorsAreLoaded() async throws {
        try await withBrowser { root, model in
            let leaf = root.appendingPathComponent("one/two/target.txt")
            try FileManager.default.createDirectory(
                at: leaf.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: leaf)
            model.reload()
            try await self.waitFor { !model.isLoading }
            let entry = try XCTUnwrap(FileSystemService().enumerateMatching(root: root, query: "target").first)
            model.revealInTree(entry)
            try await self.waitFor { model.pendingRevealTarget == entry.id }
            XCTAssertTrue(model.visibleTreeEntries.contains { $0.id == entry.id })
            XCTAssertTrue(model.selection.contains(entry.id))
        }
    }

    @MainActor
    func testTreeLoadErrorCanBeRetried() async throws {
        try await withBrowser { root, model in
            let folder = root.appendingPathComponent("not-yet-present")
            model.toggleExpanded(folder)
            try await self.waitFor { model.treeLoadErrors[folder.path] != nil }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data().write(to: folder.appendingPathComponent("recovered.txt"))
            model.retryTreeChildren(folder)
            try await self.waitFor { !model.loadingTreePaths.contains(folder.path) }
            XCTAssertNil(model.treeLoadErrors[folder.path])
            XCTAssertEqual(model.treeChildren[folder.path]?.map(\.name), ["recovered.txt"])
        }
    }

    @MainActor
    func testRestoredTreeRetainsExpandedChildrenAndNestedSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let leaf = sub.appendingPathComponent("selected.txt")
        try Data().write(to: leaf)
        let state = TabState(
            folderBookmark: try PersistenceService.makeBookmark(for: root),
            selectedURLPaths: [leaf.path], viewMode: .tree, expandedPaths: [sub.path], treeScrollPath: leaf.path)
        let model = FolderBrowserViewModel(state: state)
        try await waitFor { !model.isLoading && model.loadingTreePaths.isEmpty }
        XCTAssertEqual(model.selectedEntries.map(\.name), ["selected.txt"])
        XCTAssertTrue(model.visibleTreeEntries.contains { $0.name == "selected.txt" })
        XCTAssertEqual(model.treeScrollID?.lastPathComponent, "selected.txt")
    }

    @MainActor
    func testReloadUsesSortChosenWhileDirectoryWasLoading() async throws {
        let trigger = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let started = expectation(description: "reload started")
        defer { release.signal() }
        let loader: FolderBrowserViewModel.DirectoryLoader = { url, hidden, cancelled in
            if trigger.wait(timeout: .now()) == .success {
                started.fulfill()
                _ = release.wait(timeout: .now() + 3)
            }
            return try FileSystemService().enumerateDirectory(at: url, includingHidden: hidden, isCancelled: cancelled)
        }
        try await withBrowser(directoryLoader: loader) { root, model in
            try Data().write(to: root.appendingPathComponent("a.txt"))
            try Data().write(to: root.appendingPathComponent("b.txt"))
            trigger.signal()
            model.reload()
            await self.fulfillment(of: [started], timeout: 2)
            model.setSort(.name)  // Toggle the current name sort to descending.
            release.signal()
            try await self.waitFor { !model.isLoading }
            XCTAssertEqual(model.entries.map(\.name), ["b.txt", "a.txt"])
        }
    }

    @MainActor
    func testRecursiveSearchSelectionResolvesOutsideRootListing() async throws {
        try await withBrowser { root, model in
            let sub = root.appendingPathComponent("sub")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try Data().write(to: sub.appendingPathComponent("target.txt"))
            model.searchQuery = "target"
            try await self.waitFor { !model.isSearching }
            let match = try XCTUnwrap(model.visibleEntries.first)
            model.replaceSelection(match.id)
            XCTAssertEqual(model.selectedEntries.map(\.name), ["target.txt"])
        }
    }

    @MainActor
    func testRecentProjectSearchDeduplicatesNestedRoots() async throws {
        try await withBrowser { root, model in
            let sub = root.appendingPathComponent("sub")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try Data().write(to: sub.appendingPathComponent("artifact.pdf"))
            let saved = SavedFileSearch(name: "Artifacts", query: "", filter: .init(filesOnly: true), projectScope: true)
            model.applySearch(saved, projectRoots: [root, sub, root])
            try await self.waitFor { !model.isSearching }
            XCTAssertTrue(model.isFiltering)
            XCTAssertEqual(model.searchRoots.count, 1)
            XCTAssertEqual(model.visibleEntries.map(\.name), ["artifact.pdf"])
        }
    }

    @MainActor
    private func withBrowser(
        directoryLoader: FolderBrowserViewModel.DirectoryLoader? = nil,
        _ body: (URL, FolderBrowserViewModel) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = FolderBrowserViewModel(watchingDirectories: false, directoryLoader: directoryLoader)
        model.openFolder(root)
        try await waitFor { !model.isLoading }
        try await body(root, model)
    }

    @MainActor
    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Browser work did not finish")
    }
}
