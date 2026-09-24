import SwiftUI

struct VideoDetailPinnedProgressBar: View {
    static let height: CGFloat = 18
    static let visibleHeight: CGFloat = 3

    @ObservedObject var playerViewModel: PlayerStateViewModel
    @ObservedObject var playbackClock: PlayerPlaybackClock
    let onPrepareSeek: (Double) -> Void
    @State var isScrubbing = false
    @State var scrubProgress = 0.0
    @State var lastPreparedProgress = -1.0

    init(
        playerViewModel: PlayerStateViewModel,
        onPrepareSeek: @escaping (Double) -> Void
    ) {
        _playerViewModel = ObservedObject(wrappedValue: playerViewModel)
        _playbackClock = ObservedObject(wrappedValue: playerViewModel.playbackClock)
        self.onPrepareSeek = onPrepareSeek
    }

    var body: some View {
        GeometryReader { proxy in
            VideoDetailPinnedStaticProgressTrack(progress: displayedProgress)
                .contentShape(Rectangle())
                .gesture(progressActions.progressDragGesture(width: proxy.size.width))
                .accessibilityElement()
                .accessibilityLabel("视频进度")
                .accessibilityValue(accessibilityValue)
                .accessibilityAdjustableAction { direction in
                    progressActions.handleAccessibilityAdjustment(direction)
                }
                .allowsHitTesting(canSeek)
                .disabled(!canSeek)
        }
        .frame(height: Self.height)
    }

    private var progressActions: VideoDetailPinnedProgressBarActions {
        VideoDetailPinnedProgressBarActions(
            playerViewModel: playerViewModel,
            canSeek: canSeek,
            displayedProgress: displayedProgress,
            accessibilityStep: accessibilityStep,
            isScrubbing: $isScrubbing,
            scrubProgress: $scrubProgress,
            lastPreparedProgress: $lastPreparedProgress,
            onPrepareSeek: onPrepareSeek
        )
    }
}
