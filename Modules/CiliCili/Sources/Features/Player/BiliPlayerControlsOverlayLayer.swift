import SwiftUI
import UIKit

struct BiliPlayerControlsOverlayLayer: View {
    @AppStorage(LibraryStore.playerControlEdgeScrimEnabledKey) private var isEdgeScrimEnabled = true
    let state: BiliPlayerSurfaceChromeState
    let playbackControls: AnyView
    let usesFullscreenSafeArea: Bool

    init(
        state: BiliPlayerSurfaceChromeState,
        playbackControls: AnyView,
        usesFullscreenSafeArea: Bool = false
    ) {
        self.state = state
        self.playbackControls = playbackControls
        self.usesFullscreenSafeArea = usesFullscreenSafeArea
    }

    var body: some View {
        let safeAreaInsets = PlayerControlsSafeAreaInsets.current(
            isFullscreenActive: state.isFullscreenActive || usesFullscreenSafeArea
        )
        let topInset = max(safeAreaInsets.top, state.contentInsets.top)
        let leadingInset = max(safeAreaInsets.leading, state.contentInsets.leading)
        let bottomInset = max(safeAreaInsets.bottom, state.contentInsets.bottom)
        let trailingInset = max(safeAreaInsets.trailing, state.contentInsets.trailing)
        ZStack(alignment: .bottom) {
            if isEdgeScrimEnabled, state.showsActivePlaybackControls {
                PlayerControlEdgeScrimLayer(contentInsets: state.contentInsets)
                    .transition(.opacity)
                    .zIndex(1)
            }

            if state.showsActivePlaybackControls, let topLeadingControlsAccessory = state.topLeadingControlsAccessory {
                topLeadingControlsAccessory
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, topControlsPadding + topInset)
                    .padding(.leading, horizontalControlsPadding + state.controlsHorizontalInset + leadingInset)
                    .transition(.opacity)
                    .zIndex(8)
            }

            if state.showsActivePlaybackControls, let topCenterControlsAccessory = state.topCenterControlsAccessory {
                topCenterControlsAccessory
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, topControlsPadding + topInset)
                    .transition(.opacity)
                    .zIndex(8)
            }

            if state.showsActivePlaybackControls, let topTrailingControlsAccessory = state.topTrailingControlsAccessory {
                topTrailingControlsAccessory
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, topControlsPadding + topInset)
                    .padding(.trailing, horizontalControlsPadding + state.controlsHorizontalInset + trailingInset)
                    .transition(.opacity)
                    .zIndex(8)
            }

            if state.showsActivePlaybackControls {
                playbackControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.leading, horizontalControlsPadding + state.controlsHorizontalInset + leadingInset)
                    .padding(.trailing, horizontalControlsPadding + state.controlsHorizontalInset + trailingInset)
                    .padding(.bottom, bottomControlsPadding + state.controlsBottomLift + bottomInset)
                    .transition(.opacity)
                    .zIndex(7)
            }
        }
        .opacity(state.playbackControlsOpacity)
        .allowsHitTesting(state.playbackControlsAllowsHitTesting)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var usesFullscreenChromeSpacing: Bool {
        state.presentation == .fullScreen || state.isFullscreenActive || usesFullscreenSafeArea
    }

    private var topControlsPadding: CGFloat {
        usesFullscreenChromeSpacing ? 14 : 10
    }

    private var horizontalControlsPadding: CGFloat {
        usesFullscreenChromeSpacing ? 14 : 10
    }

    private var bottomControlsPadding: CGFloat {
        usesFullscreenChromeSpacing ? 14 : 8
    }
}

private struct PlayerControlEdgeScrimLayer: View {
    let contentInsets: EdgeInsets

    var body: some View {
        GeometryReader { proxy in
            let visibleWidth = max(1, proxy.size.width - contentInsets.leading - contentInsets.trailing)
            let visibleHeight = max(1, proxy.size.height - contentInsets.top - contentInsets.bottom)
            let height = min(max(visibleHeight * 0.28, 64), 170)

            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.36), location: 0),
                        .init(color: .black.opacity(0.15), location: 0.48),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: visibleWidth, height: height)
                .frame(maxWidth: .infinity, alignment: .top)

                Spacer(minLength: 0)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.18), location: 0.52),
                        .init(color: .black.opacity(0.44), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: visibleWidth, height: height)
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
            .padding(.top, contentInsets.top)
            .padding(.bottom, contentInsets.bottom)
            .padding(.leading, contentInsets.leading)
            .padding(.trailing, contentInsets.trailing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PlayerControlsSafeAreaInsets {
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat

    static func current(isFullscreenActive: Bool) -> PlayerControlsSafeAreaInsets {
        guard isFullscreenActive,
              let insets = UIApplication.shared.playbackDetailForegroundKeyWindow?.safeAreaInsets
        else { return .zero }

        return PlayerControlsSafeAreaInsets(
            top: max(insets.top, 0),
            leading: max(insets.left, 0),
            bottom: max(insets.bottom, 0),
            trailing: max(insets.right, 0)
        )
    }

    private static let zero = PlayerControlsSafeAreaInsets(
        top: 0,
        leading: 0,
        bottom: 0,
        trailing: 0
    )
}
