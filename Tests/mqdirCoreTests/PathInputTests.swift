import XCTest
@testable import mqdirCore

final class PathInputTests: XCTestCase {
    private let home = "/Users/me"
    private let tree: [String: Bool] = [
        "/": true,
        "/Users/me": true,
        "/Users/me/Dev": true,
        "/Users/me/Dev/mq-dir": true,
        "/Users/me/Dev/mq-dir/Sources": true,
        "/Users/me/Dev/mq-dir/Sources/App.swift": false,
        "/Users/me/My Folder": true,
        "/Users/me/My Folder/a b.txt": false,
        "/Users/me/문서 폴더": true,
        "/Users/me/odd\\name": true,
        "/Users/me/notes:2": false,
    ]

    private func resolve(_ text: String, base: String? = "/Users/me/Dev") -> PathInput.Resolution {
        PathInput.resolve(text, relativeTo: base, home: home, isDirectory: { self.tree[$0] }, canonicalize: { $0 })
    }

    private func folder(_ path: String) -> PathInput.Resolution { .folder(URL(fileURLWithPath: path, isDirectory: true)) }
    private func file(_ path: String) -> PathInput.Resolution { .file(URL(fileURLWithPath: path)) }

    func testResolve_absoluteFolderAndFile() {
        XCTAssertEqual(resolve("/Users/me/Dev/mq-dir"), folder("/Users/me/Dev/mq-dir"))
        XCTAssertEqual(resolve("/Users/me/Dev/mq-dir/Sources/App.swift"), file("/Users/me/Dev/mq-dir/Sources/App.swift"))
        XCTAssertEqual(resolve("/"), folder("/"))
    }

    func testResolve_trimsWhitespaceAndUsesFirstLine() {
        XCTAssertEqual(resolve("  /Users/me/Dev/mq-dir/ \n"), folder("/Users/me/Dev/mq-dir"))
        XCTAssertEqual(resolve("\n\n/Users/me/Dev\n/Users/me/My Folder\n"), folder("/Users/me/Dev"))
        XCTAssertEqual(resolve("\t/Users/me/Dev\r\n"), folder("/Users/me/Dev"))
    }

    func testResolve_tildeAndHome() {
        XCTAssertEqual(resolve("~"), folder("/Users/me"))
        XCTAssertEqual(resolve("~/"), folder("/Users/me"))
        XCTAssertEqual(resolve("~/Dev/mq-dir"), folder("/Users/me/Dev/mq-dir"))
        XCTAssertEqual(resolve("$HOME/Dev"), folder("/Users/me/Dev"))
        XCTAssertEqual(resolve("${HOME}/Dev"), folder("/Users/me/Dev"))
    }

    func testResolve_unwrapsQuotes() {
        XCTAssertEqual(resolve("\"/Users/me/My Folder\""), folder("/Users/me/My Folder"))
        XCTAssertEqual(resolve("'~/My Folder/a b.txt'"), file("/Users/me/My Folder/a b.txt"))
        XCTAssertEqual(resolve("“~/My Folder”"), folder("/Users/me/My Folder"))
        XCTAssertEqual(resolve("`~/Dev`"), folder("/Users/me/Dev"))
        XCTAssertEqual(resolve("<~/Dev>"), folder("/Users/me/Dev"))
    }

    func testResolve_shellEscapes() {
        XCTAssertEqual(resolve("~/My\\ Folder/a\\ b.txt"), file("/Users/me/My Folder/a b.txt"))
        // A name that really contains a backslash beats the unescaped guess.
        XCTAssertEqual(resolve("~/odd\\name"), folder("/Users/me/odd\\name"))
    }

    func testResolve_fileURL() {
        XCTAssertEqual(resolve("file:///Users/me/My%20Folder/"), folder("/Users/me/My Folder"))
        XCTAssertEqual(resolve("file://localhost/Users/me/Dev"), folder("/Users/me/Dev"))
        XCTAssertEqual(resolve("file:///Users/me/My Folder/a b.txt"), file("/Users/me/My Folder/a b.txt"))
    }

    func testResolve_lineAndColumnSuffix() {
        let app = file("/Users/me/Dev/mq-dir/Sources/App.swift")
        XCTAssertEqual(resolve("/Users/me/Dev/mq-dir/Sources/App.swift:12"), app)
        XCTAssertEqual(resolve("/Users/me/Dev/mq-dir/Sources/App.swift:12:5"), app)
        XCTAssertEqual(resolve("/Users/me/Dev/mq-dir/Sources/App.swift:12:5:"), app)
        // A file whose name really ends in ":2" is taken literally.
        XCTAssertEqual(resolve("~/notes:2"), file("/Users/me/notes:2"))
    }

    func testResolve_relativeToCurrentFolder() {
        XCTAssertEqual(resolve("mq-dir/Sources"), folder("/Users/me/Dev/mq-dir/Sources"))
        XCTAssertEqual(resolve("../My Folder"), folder("/Users/me/My Folder"))
        XCTAssertEqual(resolve("./mq-dir"), folder("/Users/me/Dev/mq-dir"))
        XCTAssertEqual(resolve("Dev", base: nil), folder("/Users/me/Dev"))
    }

    func testResolve_collapsesDotSegmentsAndSlashes() {
        XCTAssertEqual(resolve("/Users/me//Dev/./mq-dir/Sources/.."), folder("/Users/me/Dev/mq-dir"))
    }

    func testResolve_hangulName() {
        XCTAssertEqual(resolve("~/문서 폴더"), folder("/Users/me/문서 폴더"))
    }

    func testResolve_notFoundCarriesExpandedPath() {
        XCTAssertEqual(resolve("~/Nope/x.txt"), .notFound("/Users/me/Nope/x.txt"))
        XCTAssertEqual(resolve("\"~/Nope\""), .notFound("/Users/me/Nope"))
    }

    func testResolve_emptyInput() {
        XCTAssertEqual(resolve(""), .empty)
        XCTAssertEqual(resolve("  \n\t "), .empty)
        XCTAssertEqual(resolve("\"\""), .empty)
    }

    func testResolve_usesCanonicalSpelling() {
        let resolution = PathInput.resolve(
            "~/dev", relativeTo: nil, home: home,
            isDirectory: { $0.lowercased() == "/users/me/dev" ? true : nil },
            canonicalize: { _ in "/Users/me/Dev" })
        XCTAssertEqual(resolution, folder("/Users/me/Dev"))
    }

    func testPastedPath_onlyForPathLikeText() {
        XCTAssertEqual(PathInput.pastedPath("/Users/me/Dev\n"), "/Users/me/Dev")
        XCTAssertEqual(PathInput.pastedPath("~/Dev"), "~/Dev")
        XCTAssertEqual(PathInput.pastedPath("'~/My Folder'"), "~/My Folder")
        XCTAssertEqual(PathInput.pastedPath("$HOME/Dev"), "$HOME/Dev")
        XCTAssertEqual(PathInput.pastedPath("file:///Users/me/My%20Folder"), "/Users/me/My Folder")
        XCTAssertNil(PathInput.pastedPath("Sources"))
        XCTAssertNil(PathInput.pastedPath("hello world"))
        XCTAssertNil(PathInput.pastedPath("https://mqdir.com"))
        XCTAssertNil(PathInput.pastedPath(""))
        XCTAssertNil(PathInput.pastedPath(nil))
    }

    // MARK: Completion

    private let folders: [String: [String]] = [
        "/": ["Users", "Applications"],
        "/Users/me": ["Dev", "Desktop", "Documents", "Downloads", ".config"],
        "/Users/me/Dev": ["mq-dir", "mq-dir-web", "playground"],
    ]

    private func complete(_ text: String, limit: Int = 8) -> [PathInput.Completion] {
        PathInput.completions(for: text, relativeTo: "/Users/me/Dev", home: home, limit: limit,
                              subfolders: { self.folders[$0] ?? [] })
    }

    func testCompletions_prefixMatchKeepsTypedPrefix() {
        XCTAssertEqual(complete("~/D"), [
            .init(name: "Desktop", text: "~/Desktop/", path: "/Users/me/Desktop"),
            .init(name: "Dev", text: "~/Dev/", path: "/Users/me/Dev"),
            .init(name: "Documents", text: "~/Documents/", path: "/Users/me/Documents"),
            .init(name: "Downloads", text: "~/Downloads/", path: "/Users/me/Downloads"),
        ])
        XCTAssertEqual(complete("/Users/me/Dev/mq").map(\.text), ["/Users/me/Dev/mq-dir/", "/Users/me/Dev/mq-dir-web/"])
        XCTAssertEqual(complete("/U").map(\.path), ["/Users"])
    }

    func testCompletions_caseInsensitive() {
        XCTAssertEqual(complete("~/dev").map(\.text), ["~/Dev/"])
    }

    func testCompletions_trailingSlashListsAllVisibleChildren() {
        XCTAssertEqual(complete("~/").map(\.name), ["Desktop", "Dev", "Documents", "Downloads"])
        XCTAssertEqual(complete("~/", limit: 2).map(\.name), ["Desktop", "Dev"])
    }

    func testCompletions_hiddenOnlyWhenTypingDot() {
        XCTAssertEqual(complete("~/.c").map(\.name), [".config"])
    }

    func testCompletions_relativeToCurrentFolder() {
        XCTAssertEqual(complete("pl").map(\.text), ["playground/"])
        XCTAssertEqual(complete("pl").map(\.path), ["/Users/me/Dev/playground"])
    }

    func testCompletions_hangulMatchesAcrossNormalization() {
        let nfdFolders = ["/Users/me": ["문서 폴더".decomposedStringWithCanonicalMapping]]
        let result = PathInput.completions(for: "~/문서", relativeTo: nil, home: home,
                                           subfolders: { nfdFolders[$0] ?? [] })
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].text.isDecomposedRelativeToNFC)
        XCTAssertEqual(result[0].text, "~/문서 폴더/")
    }

    func testCompletions_nothingToCompleteAgainst() {
        XCTAssertEqual(complete(""), [])
        XCTAssertEqual(complete("~"), [])
        XCTAssertEqual(complete("~/Nope/x"), [])
    }

    func testCommonCompletion() {
        XCTAssertEqual(PathInput.commonCompletion(complete("~/Do"), for: "~/Do"), nil)
        XCTAssertEqual(PathInput.commonCompletion(complete("~/Doc"), for: "~/Doc"), "~/Documents/")
        XCTAssertEqual(PathInput.commonCompletion(complete("~/Dev/m"), for: "~/Dev/m"), "~/Dev/mq-dir")
        XCTAssertEqual(PathInput.commonCompletion(complete("~/dev/MQ"), for: "~/dev/MQ"), nil)
        XCTAssertEqual(PathInput.commonCompletion([], for: "~/x"), nil)
    }

    // MARK: Real file system

    func testRealFileSystem_canonicalizesCaseAndNormalization() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathInputTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let nfd = "한글 폴더".decomposedStringWithCanonicalMapping
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(nfd).appendingPathComponent("Sub"), withIntermediateDirectories: true)
        let rootPath = PathInput.canonicalPath(root.path)

        let typed = rootPath + "/" + "한글 폴더".precomposedStringWithCanonicalMapping + "/sub"
        guard case let .folder(url) = PathInput.resolve(typed, relativeTo: nil) else {
            return XCTFail("expected a folder for \(typed)")
        }
        XCTAssertEqual(url.lastPathComponent, "Sub")
        XCTAssertTrue(url.deletingLastPathComponent().lastPathComponent.isDecomposedRelativeToNFC)

        XCTAssertEqual(PathInput.subfolderNames(rootPath), [nfd])
        XCTAssertEqual(PathInput.completions(for: rootPath + "/한", relativeTo: nil).map(\.path), [rootPath + "/" + nfd])
    }
}
