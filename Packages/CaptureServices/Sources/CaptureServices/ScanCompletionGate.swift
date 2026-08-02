/// Main-actor completion gate shared by the VisionKit delegate. It guarantees
/// that cancel, failure, finish, and SwiftUI teardown cannot resume a caller
/// more than once.
@MainActor
final class ScanCompletionGate<Value> {
    private var completion: ((Value) -> Void)?

    init(completion: @escaping (Value) -> Void) {
        self.completion = completion
    }

    func takeCompletion() -> ((Value) -> Void)? {
        defer { completion = nil }
        return completion
    }

    func release() {
        completion = nil
    }
}
