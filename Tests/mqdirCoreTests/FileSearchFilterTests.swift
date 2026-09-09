import XCTest
@testable import mqdirCore

final class FileSearchFilterTests: XCTestCase {
    func testTypeAndDateFiltersAreCombinedWithoutNameQuery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["recent.PDF", "old.pdf", "script.swift"] { try Data().write(to: root.appendingPathComponent(name)) }
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: root.appendingPathComponent("old.pdf").path)
        let filter = FileSearchFilter(category: .documents, modifiedWithinDays: 7, filesOnly: true)
        let result = try FileSystemService().enumerateMatching(root: root, query: "", filter: filter)
        XCTAssertEqual(result.map(\.name), ["recent.PDF"])
    }
    func testSavedSearchesRoundTripAndOldSettingsDefaultEmpty() throws {
        let search = SavedFileSearch(name: "Project artifacts", query: "", filter: .init(modifiedWithinDays: 7, filesOnly: true), projectScope: true)
        let original = WorkspaceSettings(savedSearches: [search])
        let restored = try JSONDecoder().decode(WorkspaceSettings.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.savedSearches, [search])
        XCTAssertTrue(try JSONDecoder().decode(WorkspaceSettings.self, from: Data("{}".utf8)).savedSearches.isEmpty)
    }
    func testReadErrorsAreReportedSeparatelyFromEmptyResults() throws {
        let diagnostics = FileSearchDiagnostics()
        let root = URL(fileURLWithPath: "/tmp/" + UUID().uuidString)
        XCTAssertTrue(try FileSystemService().enumerateMatching(root: root, query: "target", diagnostics: diagnostics).isEmpty)
        XCTAssertGreaterThan(diagnostics.errorCount, 0)
    }
}
