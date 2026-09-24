import Combine
import SwiftUI
import UIKit

/// 把详情页播放器 surface 宿主接入 SwiftUI。
///
/// SwiftUI 只更新输入值，`UIViewRepresentable` 的 UIKit view identity 在整个
/// 详情页生命周期内保持不变。清晰度切换只原位换绑新的 PlayerStateViewModel。
@MainActor
struct VideoDetailShellSurfaceRepresentable: UIViewRepresentable {
    let playerViewModel: PlayerStateViewModel
    let detailViewModel: VideoDetailViewModel
    let dependencies: AppDependencies
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let rotationCoordinator: PlaybackRotationCoordinator
    let videoAspectRatio: CGFloat
    let isBareSurfaceTransitionActive: Bool
    let retainsChromeDuringBareSurfaceTransition: Bool
    let isCollapsedChromeActive: Bool
    let onShowMoreControls: (@escaping () -> Void) -> Void
    let onDismissMoreControls: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onNavigateBack: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> VideoDetailShellSurfaceHost {
        let host = makeHost()
        context.coordinator.configure(host: host, playerViewModel: playerViewModel)
        context.coordinator.attachIfPossible(to: host)
        return host
    }

    func updateUIView(
        _ uiView: VideoDetailShellSurfaceHost,
        context: Context
    ) {
        let coordinator = context.coordinator
        coordinator.configure(host: uiView, playerViewModel: playerViewModel)
        guard !uiView.isTornDown else { return }
        coordinator.scheduleConfigurationIfNeeded(
            playerViewModel: playerViewModel,
            videoAspectRatio: videoAspectRatio,
            isCollapsedChromeActive: isCollapsedChromeActive,
            isBareSurfaceTransitionActive: isBareSurfaceTransitionActive,
            retainsChromeDuringBareSurfaceTransition: retainsChromeDuringBareSurfaceTransition
        )
        coordinator.attachIfPossible(to: uiView)
    }

    static func dismantleUIView(
        _ uiView: VideoDetailShellSurfaceHost,
        coordinator: Coordinator
    ) {
        coordinator.dismantle()
        uiView.tearDown()
    }

    private func makeHost() -> VideoDetailShellSurfaceHost {
        VideoDetailShellSurfaceHost(
            playerViewModel: playerViewModel,
            detailViewModel: detailViewModel,
            dependencies: dependencies,
            runtimeSettings: runtimeSettings,
            rotationCoordinator: rotationCoordinator,
            onShowMoreControls: onShowMoreControls,
            onDismissMoreControls: onDismissMoreControls,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onNavigateBack: onNavigateBack
        )
    }

    @MainActor
    final class Coordinator {
        private weak var host: VideoDetailShellSurfaceHost?
        private weak var observedPlayer: PlayerStateViewModel?
        private weak var configuredPlayer: PlayerStateViewModel?
        private var configuredAspectRatio: CGFloat?
        private var configuredCollapsedChrome: Bool?
        private var configuredBareSurface: Bool?
        private var configuredRetainsChrome: Bool?
        private var playerCancellable: AnyCancellable?
        private var attachmentRetry: Task<Void, Never>?
        private var isAttached = false
        private var isPrewarmScheduled = false
        private var isConfigurationUpdateScheduled = false

        func configure(
            host: VideoDetailShellSurfaceHost,
            playerViewModel: PlayerStateViewModel
        ) {
            if self.host !== host {
                isAttached = false
            }
            self.host = host
            guard observedPlayer !== playerViewModel else { return }
            playerCancellable = nil
            observedPlayer = playerViewModel
            isPrewarmScheduled = false
            playerCancellable = playerViewModel.$hasPresentedPlayback
                .removeDuplicates()
                .filter { $0 }
                .prefix(1)
                .sink { [weak self] _ in
                    guard let self, !self.isPrewarmScheduled else { return }
                    self.isPrewarmScheduled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        guard let self, let host = self.host else { return }
                        host.prewarmRotationChrome()
                }
            }
        }

        func scheduleConfigurationIfNeeded(
            playerViewModel: PlayerStateViewModel,
            videoAspectRatio: CGFloat,
            isCollapsedChromeActive: Bool,
            isBareSurfaceTransitionActive: Bool,
            retainsChromeDuringBareSurfaceTransition: Bool
        ) {
            let changed = configuredPlayer !== playerViewModel
                || configuredAspectRatio != videoAspectRatio
                || configuredCollapsedChrome != isCollapsedChromeActive
                || configuredBareSurface != isBareSurfaceTransitionActive
                || configuredRetainsChrome != retainsChromeDuringBareSurfaceTransition
            guard changed else { return }

            configuredPlayer = playerViewModel
            configuredAspectRatio = videoAspectRatio
            configuredCollapsedChrome = isCollapsedChromeActive
            configuredBareSurface = isBareSurfaceTransitionActive
            configuredRetainsChrome = retainsChromeDuringBareSurfaceTransition
            guard !isConfigurationUpdateScheduled else { return }

            isConfigurationUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let host = self.host,
                      let playerViewModel = self.configuredPlayer,
                      !host.isTornDown
                else {
                    self?.isConfigurationUpdateScheduled = false
                    return
                }

                host.setPlayerViewModel(playerViewModel)
                if let videoAspectRatio = self.configuredAspectRatio {
                    host.setVideoAspectRatio(videoAspectRatio)
                }
                if let isCollapsedChromeActive = self.configuredCollapsedChrome {
                    host.setCollapsedChromeActive(isCollapsedChromeActive)
                }
                if let isBareSurfaceTransitionActive = self.configuredBareSurface {
                    host.setBareSurfaceTransitionActive(
                        isBareSurfaceTransitionActive,
                        retainsChromeTree: self.configuredRetainsChrome ?? false
                    )
                    if isBareSurfaceTransitionActive {
                        host.cancelRotationChromePrewarm()
                    }
                }
                self.isConfigurationUpdateScheduled = false
            }
        }

        func attachIfPossible(to host: VideoDetailShellSurfaceHost) {
            guard !isAttached else { return }
            guard let parent = nearestViewController(from: host) else {
                scheduleAttachmentRetry(for: host)
                return
            }
            cancelAttachmentRetry()
            host.attach(to: parent)
            isAttached = true
        }

        func cancelAttachmentRetry() {
            attachmentRetry?.cancel()
            attachmentRetry = nil
        }

        func dismantle() {
            cancelAttachmentRetry()
            playerCancellable = nil
            observedPlayer = nil
            configuredPlayer = nil
            configuredAspectRatio = nil
            configuredCollapsedChrome = nil
            configuredBareSurface = nil
            configuredRetainsChrome = nil
            isConfigurationUpdateScheduled = false
            host = nil
            isAttached = false
        }

        private func scheduleAttachmentRetry(for host: VideoDetailShellSurfaceHost) {
            guard attachmentRetry == nil else { return }
            attachmentRetry = Task { @MainActor [weak self, weak host] in
                for _ in 0..<8 {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: .milliseconds(16))
                    guard let self, let host, !Task.isCancelled else { return }
                    if self.nearestViewController(from: host) != nil {
                        self.attachmentRetry = nil
                        self.attachIfPossible(to: host)
                        return
                    }
                }
                self?.attachmentRetry = nil
            }
        }

        private func nearestViewController(from view: UIView) -> UIViewController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let viewController = current as? UIViewController {
                    return viewController
                }
                responder = current.next
            }
            return nil
        }
    }
}
