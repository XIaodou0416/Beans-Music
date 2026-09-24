import Foundation
import SwiftUI

struct BiliPlayerViewContent: View {
    let context: BiliPlayerViewRenderContext
    let renderState: BiliPlayerViewRenderState
    @State private var isMoreControlsPresented = false
    @State private var showsRateChoices = false

    var body: some View {
        BiliPlayerSurfaceChrome(
            playbackSurface: AnyView(surfaceGestureLayer),
            state: surfaceChromeState,
            speedBoostModel: context.speedBoostModel,
            seekPreviewModel: context.seekPreviewModel,
            playbackControls: AnyView(playbackControls)
        )
        .sheet(isPresented: $isMoreControlsPresented) {
            BiliPlayerMoreControlsSheet(
                viewModel: context.viewModel,
                configuration: context.configuration,
                showsRateChoices: $showsRateChoices
            )
        }
    }

    private var surfaceGestureLayer: some View {
        BiliPlayerSurfaceGestureLayerHost(
            content: playbackSurface,
            visibilityActions: renderState.visibilityActions,
            speedBoostActions: renderState.speedBoostActions,
            viewModel: context.viewModel,
            allowsDoubleTapPlaybackToggle: context.configuration.allowsDoubleTapPlaybackToggle,
            seekPreviewModel: context.seekPreviewModel,
            seekPreviewAPI: context.seekPreviewAPI,
            seekPreviewContext: context.seekPreviewContext,
            holdCurrentFrameForSeek: context.holdCurrentFrameForSeek,
            prepareUserSeekWarmup: context.prepareUserSeekWarmup,
            resetPreparedScrubProgress: context.resetPreparedScrubProgress
        )
    }

    private var playbackSurface: some View {
        VideoSurfaceView(
            viewModel: context.viewModel,
            prefersNativePlaybackControls: false,
            isPictureInPictureEnabled: context.isPictureInPictureEnabled,
            disablesImplicitLayoutAnimations: context.configuration.isLayoutTransitioning
                || context.configuration.disablesSurfaceImplicitLayoutAnimations,
            usesLiveSurfaceDuringLayoutTransition: context.configuration.usesLiveSurfaceDuringLayoutTransition,
            isLayoutTransitioningForSurfaceHandoff: context.configuration.isLayoutTransitioning
        )
    }

    private var playbackControls: some View {
        BiliPlayerNativeControlsHost(
            context: context,
            renderState: renderState,
            actions: nativePlaybackControlsActions
        )
    }

    private var nativePlaybackControlsActions: PlayerNativePlaybackControlsActions {
        BiliPlayerNativeControlsActionBuilder(
            viewModel: context.viewModel,
            configuration: context.configuration,
            visibilityActions: renderState.visibilityActions,
            seekPreviewModel: context.seekPreviewModel,
            seekPreviewAPI: context.seekPreviewAPI,
            seekPreviewContext: context.seekPreviewContext,
            holdCurrentFrameForSeek: context.holdCurrentFrameForSeek,
            prepareUserSeekWarmup: context.prepareUserSeekWarmup,
            resetPreparedScrubProgress: context.resetPreparedScrubProgress
        ).actions
    }

    private var surfaceChromeState: BiliPlayerSurfaceChromeState {
        BiliPlayerSurfaceChromeState(
            presentation: context.configuration.presentation,
            surfaceOverlay: context.configuration.surfaceOverlay,
            rotationSnapshot: context.rotationTransitionSnapshotModel.snapshot,
            seekSnapshot: context.seekTransitionSnapshotModel.snapshot,
            appBackgroundRecoverySnapshot: context.appBackgroundRecoverySnapshotModel.snapshot,
            rotationFallbackCoverURL: context.rotationFallbackCoverURL,
            rotationSnapshotOpacity: context.rotationTransitionSnapshotModel.opacity,
            seekSnapshotOpacity: context.seekTransitionSnapshotModel.opacity,
            appBackgroundRecoverySnapshotOpacity: context.appBackgroundRecoverySnapshotModel.opacity,
            constrainsRotationSnapshotToVideoAspect: context.configuration.isFullscreenActive
                || context.configuration.isLayoutTransitioning,
            showsPlayerLoadingChrome: renderState.showsPlayerLoadingChrome,
            isBuffering: context.surfaceState.isBuffering,
            isPlaying: context.surfaceState.isPlaying,
            hasPresentedPlayback: context.surfaceState.hasPresentedPlayback,
            showsInlineLoadingProgress: renderState.showsInlineLoadingProgress,
            isUserSeeking: context.surfaceState.isUserSeeking,
            showsActivePlaybackControls: renderState.showsActivePlaybackControls,
            playbackControlsOpacity: context.playbackControlsVisibility.opacity,
            playbackControlsAllowsHitTesting: context.playbackControlsVisibility.acceptsHitTesting,
            topLeadingControlsAccessory: context.configuration.topLeadingControlsAccessory,
            topCenterControlsAccessory: nil,
            topTrailingControlsAccessory: context.configuration.showsMoreControls
                ? AnyView(moreControlsButton)
                : nil,
            isFullscreenActive: context.configuration.isFullscreenActive,
            controlsBottomLift: context.configuration.controlsBottomLift,
            controlsHorizontalInset: context.configuration.controlsHorizontalInset,
            contentInsets: EdgeInsets(),
            errorMessage: context.surfaceState.errorMessage
        )
    }

    private var moreControlsButton: some View {
        BiliPlayerMoreControlsButton(
            open: {
                showsRateChoices = false
                isMoreControlsPresented = true
            }
        )
    }
}

private struct BiliPlayerMoreControlsButton: View {
    @Environment(\.playerNativeControlMetrics) private var metrics
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: metrics.controlHeight, height: metrics.controlHeight)
        }
        .biliPlayerCompactGlassCircle(metrics: metrics)
        .accessibilityLabel("更多播放设置")
        .accessibilityIdentifier("ui.player.more")
    }

    private var iconSize: CGFloat {
        metrics.iconSize + 3
    }
}

private struct BiliPlayerMoreControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject var viewModel: PlayerStateViewModel
    let configuration: BiliPlayerViewConfiguration
    @Binding var showsRateChoices: Bool

    var body: some View {
        NavigationStack {
            List {
                if let moreControlsContent = configuration.moreControlsContent {
                    moreControlsContent
                }

                if showsRateChoices {
                    ForEach(BiliPlaybackRate.allCases) { rate in
                        Button {
                            viewModel.setPlaybackRate(rate)
                            dismiss()
                        } label: {
                            Label(
                                rate.title,
                                systemImage: rate == viewModel.playbackRate ? "checkmark" : "speedometer"
                            )
                        }
                    }
                } else if !configuration.replacesStandardMoreControls {
                    if configuration.onShowDanmakuSettings != nil || configuration.onToggleDanmaku != nil {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                showDanmakuSettings()
                            }
                        } label: {
                            Label("弹幕设置", systemImage: "text.bubble")
                        }
                    }

                    Button {
                        showsRateChoices = true
                    } label: {
                        HStack {
                            Label("倍速", systemImage: "speedometer")
                            Spacer()
                            Text(viewModel.playbackRate.title)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Label("视频格式：\(videoFormatTitle)", systemImage: "film")
                        .foregroundStyle(.secondary)

                    Label("解码：\(decodeTitle)", systemImage: "cpu")
                        .foregroundStyle(.secondary)

                    Toggle(isOn: Binding(
                        get: { libraryStore.playerPerformanceOverlayEnabled },
                        set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
                    )) {
                        Label("播放性能诊断", systemImage: "waveform.path.ecg.rectangle")
                    }

                    Toggle(isOn: Binding(
                        get: { libraryStore.playerControlEdgeScrimEnabled },
                        set: { libraryStore.setPlayerControlEdgeScrimEnabled($0) }
                    )) {
                        Label("播放控件边缘遮罩", systemImage: "rectangle.topthird.inset.filled")
                    }
                }
            }
            .foregroundStyle(.primary)
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.clear)
            .listStyle(.plain)
            .navigationTitle(
                showsRateChoices
                    ? "倍速"
                    : (configuration.replacesStandardMoreControls ? "更多设置" : "播放设置")
            )
            .navigationBarTitleDisplayMode(.inline)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .background {
            BiliPlayerGlassSheetBackground()
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    private func showDanmakuSettings() {
        if let onShowDanmakuSettings = configuration.onShowDanmakuSettings {
            onShowDanmakuSettings()
        } else {
            configuration.onToggleDanmaku?()
        }
    }

    private var decodeTitle: String {
        let diagnostics = viewModel.engineDiagnostics
        var parts = [diagnostics.decodePath.title]
        if diagnostics.hardwareDecodeRequested {
            parts.append("硬解")
        }
        if let isHardwareDecodeCompatible = diagnostics.isHardwareDecodeCompatible {
            parts.append(isHardwareDecodeCompatible ? "硬解兼容" : "硬解不兼容")
        }
        return parts.joined(separator: " · ")
    }

    private var videoFormatTitle: String {
        let diagnostics = viewModel.engineDiagnostics
        var parts = [String]()
        if let codec = diagnostics.codec, !codec.isEmpty {
            parts.append(codecDisplayName(codec))
        }
        if let resolution = diagnostics.resolution, !resolution.isEmpty {
            parts.append(resolution)
        }
        if let frameRate = diagnostics.frameRate, !frameRate.isEmpty {
            parts.append(frameRate)
        }
        if let dynamicRangeTitle {
            parts.append(dynamicRangeTitle)
        }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        let description = viewModel.engineDiagnostics.compactDescription
        return description.isEmpty ? "未知" : description
    }

    private var dynamicRangeTitle: String? {
        switch viewModel.engineDiagnostics.dynamicRange {
        case .sdr:
            return nil
        case .hdr10:
            return "HDR"
        case .hlg:
            return "HLG"
        case .dolbyVision:
            return "杜比视界"
        }
    }

    private func codecDisplayName(_ codec: String) -> String {
        switch codec.uppercased() {
        case "AVC":
            return "H.264 / AVC"
        case "HEVC":
            return "HEVC / H.265"
        default:
            return codec
        }
    }
}
