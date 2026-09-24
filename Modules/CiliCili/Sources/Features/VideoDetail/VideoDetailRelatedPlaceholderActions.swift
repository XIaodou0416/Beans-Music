import Foundation

@MainActor
struct VideoDetailRelatedPlaceholderActions {
    let retryRelated: () async -> Void

    func retry() {
        Task { await retryRelated() }
    }
}
