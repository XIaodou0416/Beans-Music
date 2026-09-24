import Foundation

@MainActor
struct HomeFeedScreenActionStore {
    let preload = HomeFeedPreloadActions()
    let refresh = HomeFeedRefreshActions()
    let detailOpen = HomeFeedDetailOpenActions()
    let lifecycle = HomeFeedLifecycleActions()
    let mode = HomeFeedModeActions()
    let scroll = HomeFeedScrollActions()
    let nativeRefresh = HomeNativeRefreshActionStore()
    let card = HomeFeedCardActions()
}
