import Foundation

struct VideoCoverLoadedState: Equatable {
    private(set) var loadedIdentity: String?

    func isLoaded(identity: String) -> Bool {
        loadedIdentity == identity
    }

    mutating func update(phase: RemoteImageLoadingPhase, identity: String) {
        switch phase {
        case .loaded:
            loadedIdentity = identity
        case .idle, .loading, .failed:
            if loadedIdentity != identity {
                loadedIdentity = nil
            }
        }
    }
}
