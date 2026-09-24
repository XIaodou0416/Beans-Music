import Foundation

nonisolated struct VideoDetailRelatedRenderChangeSignature: Equatable {
    let relatedSignature: VideoDetailRelatedListSignature
    let state: LoadingState
    let lastLoadTimedOut: Bool
}
