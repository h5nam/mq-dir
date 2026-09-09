import AppKit
import XCTest

final class CutPasteboardTests: XCTestCase {
    @MainActor
    func testMoveCompletionPreservesNewClipboardContents() {
        let pb = NSPasteboard(name: .init(UUID().uuidString))
        defer { pb.releaseGlobally() }
        pb.setString("old", forType: .string)
        let revision = pb.changeCount
        pb.clearContents()
        pb.setString("new clipboard", forType: .string)
        CutPasteboard.complete(pb, changeCount: revision, remainingURLs: [])
        XCTAssertEqual(pb.string(forType: .string), "new clipboard")
    }

    @MainActor
    func testPartialMoveRetainsOnlyRetryURLsAndCutMarker() {
        let pb = NSPasteboard(name: .init(UUID().uuidString))
        defer { pb.releaseGlobally() }
        let failed = URL(fileURLWithPath: "/tmp/mqdir-fixture-failed.txt")
        pb.setString("old", forType: .string)
        CutPasteboard.complete(pb, changeCount: pb.changeCount, remainingURLs: [failed])
        let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(urls, [failed])
        XCTAssertTrue(pb.types?.contains(CutPasteboard.markerType) == true)
    }

    @MainActor
    func testSuccessfulMoveClearsOriginalClipboard() {
        let pb = NSPasteboard(name: .init(UUID().uuidString))
        defer { pb.releaseGlobally() }
        pb.setString("old", forType: .string)
        CutPasteboard.complete(pb, changeCount: pb.changeCount, remainingURLs: [])
        XCTAssertNil(pb.string(forType: .string))
        XCTAssertFalse(pb.types?.contains(CutPasteboard.markerType) == true)
    }
}
