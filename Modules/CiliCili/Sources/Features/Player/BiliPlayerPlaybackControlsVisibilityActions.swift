import SwiftUI

struct BiliPlayerPlaybackControlsVisibilityActions {
    let playbackControlsVisibility: PlayerPlaybackControlsVisibilityModel
    let configuration: BiliPlayerViewConfiguration

    func syncSecondaryControlsPresentation(_ isPresented: Bool) {
        playbackControlsVisibility.syncSecondaryControlsPresentation(
            isPresented,
            showsPlaybackControls: configuration.showsPlaybackControls,
            isLayoutTransitioning: configuration.isLayoutTransitioning
        )
    }

    func toggle() {
        playbackControlsVisibility.toggle(
            showsPlaybackControls: configuration.showsPlaybackControls,
            isLayoutTransitioning: configuration.isLayoutTransitioning
        )
    }

    func showAndSchedule() {
        playbackControlsVisibility.showAndSchedule(
            showsPlaybackControls: configuration.showsPlaybackControls,
            isLayoutTransitioning: configuration.isLayoutTransitioning
        )
    }

    func markInteraction(keepsVisible: Bool = false) {
        playbackControlsVisibility.markInteraction(
            keepsVisible: keepsVisible,
            showsPlaybackControls: configuration.showsPlaybackControls,
            isLayoutTransitioning: configuration.isLayoutTransitioning
        )
    }

    func show(scheduleAutoHide: Bool, animated: Bool = true) {
        playbackControlsVisibility.show(
            scheduleAutoHide: scheduleAutoHide,
            animated: animated,
            showsPlaybackControls: configuration.showsPlaybackControls,
            isLayoutTransitioning: configuration.isLayoutTransitioning
        )
    }

    func scheduleAutoHide() {
        playbackControlsVisibility.scheduleAutoHide(
            showsPlaybackControls: configuration.showsPlaybackControls,
            isLayoutTransitioning: configuration.isLayoutTransitioning
        )
    }

    func cancelAutoHide() {
        playbackControlsVisibility.cancelAutoHide()
    }
}
