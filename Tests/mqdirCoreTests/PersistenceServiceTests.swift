import XCTest
@testable import mqdirCore

final class PersistenceServiceTests: XCTestCase {
    private var tempDirectory: URL!
    private var stateURL: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mqdir-persistence-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        stateURL = tempDirectory.appendingPathComponent("state.json", isDirectory: false)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        stateURL = nil
    }

    // MARK: - Round trip

    func testSaveAndLoadRoundTrip() throws {
        let service = try PersistenceService(stateURL: stateURL)
        let original = sampleWindowState()

        try service.saveState(original)
        let reloaded = service.loadState()

        XCTAssertEqual(reloaded, original)
    }

    /// Headline product promise check: the UI you left is the UI you return
    /// to. Constructs a *fresh* PersistenceService over the same file URL
    /// to mimic an app relaunch and asserts non-default values survive.
    func testFreshServiceLoadsPreviouslySavedState() throws {
        let writer = try PersistenceService(stateURL: stateURL)
        let original = sampleWindowState()
        try writer.saveState(original)

        let reader = try PersistenceService(stateURL: stateURL)
        let loaded = reader.loadState()

        XCTAssertEqual(loaded, original)
    }

    // MARK: - Missing / corrupt files

    func testLoadReturnsNilForMissingFile() throws {
        let service = try PersistenceService(stateURL: stateURL)
        XCTAssertNil(service.loadState())
    }

    func testLoadReturnsNilForCorruptFile() throws {
        let service = try PersistenceService(stateURL: stateURL)
        try Data("not json at all".utf8).write(to: stateURL)
        XCTAssertNil(service.loadState(), "corrupt JSON must degrade to nil, not throw")
    }

    func testLoadReturnsNilForEmptyFile() throws {
        let service = try PersistenceService(stateURL: stateURL)
        try Data().write(to: stateURL)
        XCTAssertNil(service.loadState())
    }

    // MARK: - Bookmarks

    func testBookmarkRoundTripsForExistingDir() throws {
        // Create a real subdir under our temp scratch space — security-scoped
        // bookmark creation needs an openable path, and a symlinked location
        // like /tmp can fail with "Could not open() the item".
        let target = tempDirectory.appendingPathComponent("bookmarkTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let bookmark = try PersistenceService.makeBookmark(for: target)

        var pane = PaneState()
        pane.folderBookmark = bookmark
        let state = WindowState(
            layout: .four,
            focusedPaneIndex: 0,
            panes: [pane, PaneState(), PaneState(), PaneState()]
        )

        let service = try PersistenceService(stateURL: stateURL)
        try service.saveState(state)

        let loaded = try XCTUnwrap(service.loadState())
        let loadedBookmark = try XCTUnwrap(loaded.panes[0].folderBookmark)
        let resolved = try XCTUnwrap(PersistenceService.resolveBookmark(loadedBookmark))

        // Compare canonical paths to neutralize /tmp ↔ /private/tmp aliasing
        // and any volume-mount canonicalization the resolver applies.
        XCTAssertEqual(
            resolved.resolvingSymlinksInPath().path,
            target.resolvingSymlinksInPath().path
        )
    }

    // MARK: - Default-state shape

    func testEmptyStateHasFourPanes() {
        XCTAssertEqual(WindowState.empty.panes.count, 4)
        XCTAssertEqual(WindowState.empty.layout, .four)
        XCTAssertEqual(WindowState.empty.focusedPaneIndex, 0)
    }

    // MARK: - Helpers

    private func sampleWindowState() -> WindowState {
        WindowState(
            layout: .twoH,
            focusedPaneIndex: 1,
            panes: [
                PaneState(
                    folderBookmark: Data([0x01, 0x02, 0x03]),
                    sortKey: .modified,
                    sortAscending: false,
                    includeHidden: true,
                    columnWidths: PaneColumnWidths(modified: 200, size: 100, kind: 150),
                    selectedURLPaths: ["/tmp/foo.txt", "/tmp/bar.txt"]
                ),
                PaneState(
                    folderBookmark: nil,
                    sortKey: .size,
                    sortAscending: true,
                    includeHidden: false,
                    columnWidths: PaneColumnWidths(),
                    selectedURLPaths: []
                ),
                PaneState(),
                PaneState(),
            ]
        )
    }
}
