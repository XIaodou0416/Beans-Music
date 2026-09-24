import Foundation

extension VideoDetailViewModel {
    func fetchPlayURLWithTimeout(
        timeout: UInt64,
        operation: @escaping @MainActor @Sendable () async throws -> PlayURLData
    ) async throws -> PlayURLData {
        try await withThrowingTaskGroup(of: PlayURLData.self) { group -> PlayURLData in
            group.addTask(priority: .userInitiated) {
                try await operation()
            }
            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: timeout)
                throw VideoDetailLoadTimeoutError.playURL
            }
            guard let result = try await group.next() else {
                throw VideoDetailLoadTimeoutError.playURL
            }
            group.cancelAll()
            return result
        }
    }
}
