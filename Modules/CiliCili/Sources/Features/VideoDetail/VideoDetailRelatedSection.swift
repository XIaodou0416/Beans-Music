import SwiftUI

struct VideoDetailRelatedSection: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject var store: VideoDetailRelatedRenderStore
    let layoutWidth: CGFloat
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let retryRelated: () async -> Void
    @State private var preloadedRelatedVideos = Set<String>()

    var body: some View {
        let layout = VideoDetailRelatedListLayout(layoutWidth: layoutWidth)

        VideoDetailRelatedSectionContent(
            relatedItems: store.relatedItems,
            layout: layout,
            state: store.state,
            didTimeOut: store.lastLoadTimedOut,
            retryRelated: retryRelated,
            listActions: relatedListActions
        )
        .frame(width: layoutWidth, alignment: .leading)
        .padding(.top, VideoDetailRelatedStyle.sectionTopPadding)
        .padding(.bottom, VideoDetailRelatedStyle.sectionBottomPadding)
    }

    private var relatedListActions: VideoDetailRelatedListActions {
        VideoDetailRelatedListActions(beginPreload: beginRelatedPreloadIfNeeded)
    }

    private var preloadActions: VideoDetailRelatedPreloadActions {
        VideoDetailRelatedSectionPreloadActionsBuilder(
            preloadedVideoIDs: $preloadedRelatedVideos,
            api: dependencies.api,
            runtimeSettings: runtimeSettings
        )
        .actions
    }

    private func beginRelatedPreloadIfNeeded(_ video: VideoItem) async {
        await preloadActions.beginPreloadIfNeeded(video)
    }
}
