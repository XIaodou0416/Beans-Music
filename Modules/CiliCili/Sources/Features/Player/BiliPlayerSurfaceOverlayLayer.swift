import SwiftUI

struct BiliPlayerSurfaceOverlayLayer: View {
    let state: BiliPlayerSurfaceChromeState
    @ObservedObject var speedBoostModel: PlayerSpeedBoostModel
    @ObservedObject var seekPreviewModel: PlayerSeekPreviewModel

    var body: some View {
        ZStack {
            if let surfaceOverlay = state.surfaceOverlay {
                surfaceOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(1)
            }

            if state.showsPlayerLoadingChrome {
                PlayerStartupLoadingChrome(isBuffering: state.isBuffering)
                    .padding(state.presentation == .embedded ? 12 : 16)
                    .zIndex(2)
            }

            if let errorMessage = state.errorMessage {
                PlayerPlaybackErrorChrome(message: errorMessage)
                    .padding(state.presentation == .embedded ? 10 : 16)
                    .zIndex(3)
            }

            if state.showsSeekSnapshot {
                PlayerRotationTransitionSnapshotView(
                    snapshot: state.seekSnapshot,
                    fallbackCoverURL: nil,
                    constrainsToVideoAspect: false
                )
                .background(Color.black)
                .opacity(state.seekSnapshotDisplayOpacity)
                .zIndex(5)
            }

            if state.showsAppBackgroundRecoverySnapshot {
                PlayerRotationTransitionSnapshotView(
                    snapshot: state.appBackgroundRecoverySnapshot,
                    fallbackCoverURL: nil,
                    constrainsToVideoAspect: state.constrainsRotationSnapshotToVideoAspect
                )
                .background(Color.black)
                .opacity(state.appBackgroundRecoverySnapshotOpacity)
                .zIndex(6)
            }

            if state.showsRotationSnapshot {
                PlayerRotationTransitionSnapshotView(
                    snapshot: state.rotationSnapshot,
                    fallbackCoverURL: state.rotationFallbackCoverURL,
                    constrainsToVideoAspect: state.constrainsRotationSnapshotToVideoAspect
                )
                .background(Color.black)
                .opacity(state.rotationSnapshotOpacity)
                .zIndex(7)
            }

            if state.showsInlineLoadingProgress, !state.isUserSeeking {
                PlayerInlineLoadingIndicator(message: "正在缓冲")
                .padding(.top, state.presentation == .embedded ? 10 : 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(6)
            }

            if speedBoostModel.isIndicatorVisible {
                PlayerSpeedBoostIndicator(
                    phase: speedBoostModel.phase,
                    displayedRate: speedBoostModel.displayedRate
                )
                    .padding(.top, state.presentation == .embedded ? 10 : 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(6)
            }

            if let presentation = seekPreviewModel.presentation {
                PlayerSeekPreviewOverlay(presentation: presentation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private extension BiliPlayerSurfaceChromeState {
    var showsSeekSnapshot: Bool {
        seekSnapshot != nil && (isUserSeeking || seekSnapshotOpacity > 0)
    }

    var seekSnapshotDisplayOpacity: Double {
        isUserSeeking ? 1 : seekSnapshotOpacity
    }

    var showsRotationSnapshot: Bool {
        rotationSnapshotOpacity > 0
            && rotationSnapshot != nil
    }

    var showsAppBackgroundRecoverySnapshot: Bool {
        appBackgroundRecoverySnapshotOpacity > 0
            && appBackgroundRecoverySnapshot != nil
    }
}
