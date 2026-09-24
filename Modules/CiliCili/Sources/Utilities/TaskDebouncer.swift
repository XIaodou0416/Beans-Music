import Foundation

@MainActor
final class TaskDebouncer {
    private var task: Task<Void, Never>?

    func schedule(delay: Duration = .milliseconds(350), action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

