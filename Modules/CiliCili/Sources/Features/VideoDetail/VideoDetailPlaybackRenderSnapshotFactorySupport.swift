import Foundation

@MainActor
extension VideoDetailPlaybackRenderSnapshotFactory {
    var selectedPlayVariant: PlayVariant? {
        viewModel.selectedPlayVariant
    }

    var failedMessage: String? {
        if case let .failed(message) = viewModel.state {
            return message
        }
        return nil
    }

    var qualityInlineButtonTitle: String {
        VideoDetailPlaybackQualityMenuBuilder.inlineQualityButtonTitle(
            selectedPlayVariant: selectedPlayVariant,
            isSwitchingPlayQuality: viewModel.isSwitchingPlayQuality
        )
    }

    var qualityAccessoryButtonTitle: String {
        VideoDetailPlaybackQualityMenuBuilder.accessoryQualityButtonTitle(
            selectedPlayVariant: selectedPlayVariant,
            isSwitchingPlayQuality: viewModel.isSwitchingPlayQuality
        )
    }

    var qualityButtonSystemImage: String {
        viewModel.isSwitchingPlayQuality
            ? "arrow.triangle.2.circlepath"
            : "slider.horizontal.3"
    }

    var qualityMenuItems: [VideoDetailPlaybackQualityMenuItem] {
        VideoDetailPlaybackQualityMenuBuilder.makeQualityMenuItems(
            playVariants: viewModel.playVariants,
            selectedPlayVariant: selectedPlayVariant,
            pendingPlayVariantID: viewModel.pendingPlayVariantID,
            isSwitchingPlayQuality: viewModel.isSwitchingPlayQuality
        )
    }
}
