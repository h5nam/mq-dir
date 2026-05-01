import XCTest
@testable import mqdirCore

final class FileSystemServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mqdir-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testEnumerateDirectorySkipsHiddenFilesByDefault() throws {
        try writeFile("visible.txt", contents: "hello")
        try writeFile(".hidden.txt", contents: "secret")
        try makeDirectory("Folder")

        let entries = try FileSystemService().enumerateDirectory(at: tempDirectory)

        XCTAssertEqual(Set(entries.map(\.name)), ["visible.txt", "Folder"])
        XCTAssertTrue(entries.first { $0.name == "Folder" }?.isDirectory == true)
        XCTAssertEqual(entries.first { $0.name == "visible.txt" }?.size, 5)
    }

    func testEnumerateDirectoryCanIncludeHiddenFiles() throws {
        try writeFile("visible.txt", contents: "hello")
        try writeFile(".hidden.txt", contents: "secret")

        let entries = try FileSystemService().enumerateDirectory(at: tempDirectory, includingHidden: true)

        XCTAssertEqual(Set(entries.map(\.name)), ["visible.txt", ".hidden.txt"])
        XCTAssertTrue(entries.first { $0.name == ".hidden.txt" }?.isHidden == true)
    }

    func testSorterKeepsFoldersFirstThenAppliesRequestedSort() throws {
        let folder = entry(name: "z-folder", isDirectory: true, size: nil)
        let small = entry(name: "a.txt", isDirectory: false, size: 1)
        let large = entry(name: "b.txt", isDirectory: false, size: 20)

        let sorted = FileEntrySorter.sorted([large, small, folder], by: .size, ascending: false)

        XCTAssertEqual(sorted.map(\.name), ["z-folder", "b.txt", "a.txt"])
    }

    private func writeFile(_ name: String, contents: String) throws {
        let url = tempDirectory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
    }

    private func makeDirectory(_ name: String) throws {
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent(name, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func entry(name: String, isDirectory: Bool, size: Int64?) -> FileEntry {
        FileEntry(
            url: tempDirectory.appendingPathComponent(name, isDirectory: isDirectory),
            name: name,
            isDirectory: isDirectory,
            size: size,
            modificationDate: nil,
            kind: isDirectory ? "Folder" : "Document",
            isHidden: false
        )
    }
}

