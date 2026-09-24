import Foundation

enum VideoDetailPlayURLCacheResolution {
    case loaded(signpostMessage: String)
    case needsNetwork(deferredFallback: VideoDetailPlayURLFallback?)
}
