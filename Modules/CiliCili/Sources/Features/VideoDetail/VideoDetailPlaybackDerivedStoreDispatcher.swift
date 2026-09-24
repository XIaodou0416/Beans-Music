import Foundation

@MainActor
struct VideoDetailPlaybackDerivedStoreDispatcher {
    let qualityControlStore: VideoDetailQualityControlRenderStore
    let placeholderStore: VideoDetailPlayerPlaceholderRenderStore
    let pageSelectorStore: VideoDetailPageSelectorRenderStore

    func updateStores(with snapshot: VideoDetailPlaybackRenderSnapshot) {
        qualityControlStore.update(VideoDetailQualityControlRenderSnapshot(playback: snapshot))
        placeholderStore.update(VideoDetailPlayerPlaceholderRenderSnapshot(playback: snapshot))
        pageSelectorStore.update(VideoDetailPageSelectorRenderSnapshot(playback: snapshot))
    }
}
