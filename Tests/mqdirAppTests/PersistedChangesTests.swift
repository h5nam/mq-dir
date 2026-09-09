import Combine
import XCTest

final class PersistedChangesTests: XCTestCase {
    @MainActor
    func testSingleMutationSnapshotsNewValueWithoutAnotherEvent() async {
        let model = PublishedFixture()
        let saved = expectation(description: "post-mutation snapshot")
        let subscription = model.objectWillChange.persistedChanges.sink {
            XCTAssertTrue(model.previewVisible)
            saved.fulfill()
        }
        model.previewVisible = true
        await fulfillment(of: [saved], timeout: 2)
        withExtendedLifetime(subscription) {}
    }
}

private final class PublishedFixture: ObservableObject {
    @Published var previewVisible = false
}
