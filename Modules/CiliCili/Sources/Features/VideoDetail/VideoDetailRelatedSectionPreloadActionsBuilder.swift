import SwiftUI

@MainActor
struct VideoDetailRelatedSectionPreloadActionsBuilder {
    @Binding var preloadedVideoIDs: Set<String>
    let api: BiliAPIClient
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot

    var actions: VideoDetailRelatedPreloadActions {
        VideoDetailRelatedPreloadActions(
            preloadedVideoIDs: $preloadedVideoIDs,
            api: api,
            runtimeSettings: runtimeSettings
        )
    }
}
