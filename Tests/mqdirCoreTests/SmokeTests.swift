import XCTest
@testable import mqdirCore

final class SmokeTests: XCTestCase {
    func testSortKeysCoverM1ListColumns() {
        XCTAssertEqual(FileEntrySortKey.allCases, [.name, .modified, .size, .kind])
    }
}
