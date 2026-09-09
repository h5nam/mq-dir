import Combine
import Foundation

extension ObservableObjectPublisher {
    /// objectWillChange fires before @Published storage is updated. Deliver
    /// save triggers on the next main-queue turn so snapshots see the new value.
    var persistedChanges: AnyPublisher<Void, Never> {
        receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }
}
