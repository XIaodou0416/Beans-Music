import Foundation

nonisolated final class PendingTaskWaiter<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?

    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func succeed(_ value: Value) {
        complete(.success(value))
    }

    func fail(_ error: Error) {
        complete(.failure(error))
    }

    private func complete(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

extension BiliAPIClient {
    nonisolated static func awaitSharedTask<Value: Sendable>(
        _ task: Task<Value, Error>
    ) async throws -> Value {
        let waiter = PendingTaskWaiter<Value>()
        Task(priority: .utility) {
            do {
                waiter.succeed(try await task.value)
            } catch {
                waiter.fail(error)
            }
        }
        return try await withTaskCancellationHandler {
            try await waiter.value()
        } onCancel: {
            waiter.fail(CancellationError())
        }
    }
}
