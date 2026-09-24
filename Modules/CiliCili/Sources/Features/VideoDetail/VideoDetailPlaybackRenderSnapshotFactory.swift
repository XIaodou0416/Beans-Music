import Foundation

@MainActor
struct VideoDetailPlaybackRenderSnapshotFactory {
    let viewModel: VideoDetailViewModel

    var snapshot: VideoDetailPlaybackRenderSnapshot {
        VideoDetailPlaybackRenderSnapshot(
            historyVideo: viewModel.playbackOptions.recordsPlaybackHistory ? viewModel.detail : nil,
            historyCID: viewModel.playbackOptions.recordsPlaybackHistory ? viewModel.selectedCID : nil,
            duration: viewModel.detail.duration.map(TimeInterval.init),
            pages: viewModel.detail.pages ?? [],
            selectedCID: viewModel.selectedCID,
            playURLState: viewModel.playURLState,
            selectedPlayVariant: selectedPlayVariant,
            isDetailLoading: viewModel.state.isLoading,
            isDetailLoaded: viewModel.state == .loaded,
            failedMessage: failedMessage,
            isDanmakuEnabled: viewModel.isDanmakuEnabled,
            qualityInlineButtonTitle: qualityInlineButtonTitle,
            qualityAccessoryButtonTitle: qualityAccessoryButtonTitle,
            qualityButtonSystemImage: qualityButtonSystemImage,
            qualityMenuItems: qualityMenuItems,
            isSwitchingPlayQuality: viewModel.isSwitchingPlayQuality
        )
    }
}
