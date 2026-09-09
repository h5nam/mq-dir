import XCTest

final class DirectoryWatcherTests: XCTestCase {
    func testSameFolderSharesStreamAndStopsAfterLastSubscriber() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let baseline = DirectoryWatcher.activeStreamCount
        let first = DirectoryWatcher(url: root) {}
        let second = DirectoryWatcher(url: root) {}
        XCTAssertEqual(DirectoryWatcher.activeStreamCount, baseline + 1)
        first.stop()
        first.stop()
        XCTAssertEqual(DirectoryWatcher.activeStreamCount, baseline + 1)
        second.stop()
        XCTAssertEqual(DirectoryWatcher.activeStreamCount, baseline)
    }
}
