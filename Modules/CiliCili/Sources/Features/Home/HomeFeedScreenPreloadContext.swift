import SwiftUI

extension HomeFeedScreenContent {
    var preloadContext: HomeFeedPreloadContext {
        HomeFeedPreloadContextFactory.make(dependencies: dependencies)
    }
}
