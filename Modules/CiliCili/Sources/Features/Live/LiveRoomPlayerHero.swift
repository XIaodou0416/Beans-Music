import SwiftUI

struct LiveRoomPlayerHero: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject var viewModel: LiveRoomViewModel
    let isLandscape: Bool
    let fullscreenMode: PlayerFullscreenMode?
    let playerWidth: CGFloat?
    let playerHeight: CGFloat
    let loadingPlaceholder: () -> AnyView
    let onRequestFullscreen: (PlayerStateViewModel?) -> Void
    let onExitFullscreen: (PlayerStateViewModel?) -> Void

    var body: some View {
        PlaybackDetailPlayerSurface(width: playerWidth, height: playerHeight) {
            ZStack {
                if viewModel.playerViewModel != nil {
                    coordinatedLivePlayer()
                } else {
                    loadingPlaceholder()
                        .frame(width: playerWidth)
                        .frame(height: playerHeight)
                }

                streamFallbackMessage

                if viewModel.isLiveDanmakuDiagnosticsEnabled {
                    LiveDanmakuDiagnosticsOverlay(
                        store: viewModel.liveDanmakuRenderStore.diagnosticsStore,
                        usesLandscapeChrome: usesLandscapeChrome
                    )
                }
            }
        }
    }

    private var usesLandscapeChrome: Bool {
        isLandscape || fullscreenMode?.isLandscape == true
    }

    @ViewBuilder
    private var streamFallbackMessage: some View {
        if let message = viewModel.streamFallbackMessage, viewModel.playerViewModel?.hasPresentedPlayback != true {
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.56))
                .clipShape(Capsule())
        }
    }

    private func coordinatedLivePlayer() -> some View {
        LiveRoomSurfaceCoordinatorView(
            viewModel: viewModel,
            playbackSession: viewModel.playbackSession,
            dependencies: dependencies,
            usesLandscapeChrome: usesLandscapeChrome,
            usesPortraitFullscreen: fullscreenMode == .portrait,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen
        )
        .frame(width: playerWidth)
        .frame(height: playerHeight)
    }
}
