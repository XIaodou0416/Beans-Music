import AVFoundation
import Combine
import UIKit

/// 视频层协调器只负责 surface 宿主生命周期与几何更新。
/// 朝向请求和系统转场仍由详情页外壳持有，避免改变已经验证的旋转动画。
@MainActor
final class PlayerSurfaceController {
    typealias HostFactory = (PlayerStateViewModel) -> (any PlayerSurfaceHosting)?

    private weak var parentViewController: UIViewController?
    private weak var containerView: UIView?
    private let makeHost: HostFactory
    private var host: (any PlayerSurfaceHosting)?
    private var playbackSessionCancellable: AnyCancellable?
    private var playbackSessionID: ObjectIdentifier?
    private var activePlayerID: ObjectIdentifier?
    private var latestLayout: PlayerSurfaceLayout?
    private var appliedLayout: PlayerSurfaceLayout?
    private var rotationChromePrewarmCancellable: AnyCancellable?
    private var rotationChromePrewarmedPlayerID: ObjectIdentifier?

    /// Surface 的播放器替换会回传给详情页，用来维持仅与布局有关的状态订阅。
    var onActivePlayerChange: ((PlayerStateViewModel?) -> Void)?

    var isRotationChromePrewarmed: Bool {
        host?.isRotationChromePrewarmed ?? false
    }

    init(
        parentViewController: UIViewController,
        containerView: UIView,
        makeHost: @escaping HostFactory,
        onActivePlayerChange: ((PlayerStateViewModel?) -> Void)? = nil
    ) {
        self.parentViewController = parentViewController
        self.containerView = containerView
        self.makeHost = makeHost
        self.onActivePlayerChange = onActivePlayerChange
    }

    func adopt(_ host: any PlayerSurfaceHosting) {
        if let currentHost = self.host, currentHost.surfaceView === host.surfaceView {
            return
        }
        self.host = host
        activePlayerID = nil
        appliedLayout = nil
    }

    func releaseHost() -> (any PlayerSurfaceHosting)? {
        cancelRotationChromePrewarm()
        rotationChromePrewarmedPlayerID = nil
        unbindPlaybackSession()
        activePlayerID = nil
        latestLayout = nil
        appliedLayout = nil
        defer { host = nil }
        return host
    }

    func bind(_ playerViewModel: PlayerStateViewModel, layout: PlayerSurfaceLayout) {
        unbindPlaybackSession()
        latestLayout = layout
        bindActivePlayer(playerViewModel, layout: layout)
    }

    /// 让 surface 直接跟随稳定播放会话。清晰度切换导致 player 实例替换时，
    /// 详情页无需再做一次中转订阅。
    func bind(to playbackSession: PlaybackSession, layout: PlayerSurfaceLayout) {
        latestLayout = layout
        let nextSessionID = ObjectIdentifier(playbackSession)
        guard playbackSessionID != nextSessionID else {
            receiveActivePlayer(playbackSession.activePlayer, from: nextSessionID)
            updateLayout(layout)
            return
        }

        unbindPlaybackSession()
        playbackSessionID = nextSessionID
        playbackSessionCancellable = playbackSession.$activePlayer
            .receive(on: RunLoop.main)
            .sink { [weak self] playerViewModel in
                self?.receiveActivePlayer(playerViewModel, from: nextSessionID)
            }
        receiveActivePlayer(playbackSession.activePlayer, from: nextSessionID)
    }

    func unbindPlaybackSession() {
        playbackSessionCancellable = nil
        playbackSessionID = nil
    }

    func updateLayout(_ layout: PlayerSurfaceLayout) {
        latestLayout = layout
        guard let host else { return }
        let previousLayout = appliedLayout
        if previousLayout == nil || previousLayout!.frame != layout.frame {
            host.surfaceView.frame = layout.frame
        }
        if previousLayout == nil || previousLayout!.videoAspectRatio != layout.videoAspectRatio {
            host.setVideoAspectRatio(layout.videoAspectRatio)
        }
        if previousLayout == nil || previousLayout!.videoGravity != layout.videoGravity {
            host.setVideoGravity(layout.videoGravity)
        }
        if !layout.isTransitioning,
           (previousLayout == nil
                || previousLayout!.usesLandscapeChrome != layout.usesLandscapeChrome
                || previousLayout!.isTransitioning) {
            host.setLandscape(layout.usesLandscapeChrome)
        }
        if !layout.isTransitioning,
           (previousLayout == nil
                || previousLayout!.usesPortraitFullscreen != layout.usesPortraitFullscreen
                || previousLayout!.isTransitioning) {
            host.setPortraitFullscreen(layout.usesPortraitFullscreen)
        }
        appliedLayout = layout
    }

    func setVideoAspectRatio(_ aspectRatio: CGFloat) {
        latestLayout?.videoAspectRatio = aspectRatio
        appliedLayout?.videoAspectRatio = aspectRatio
        host?.setVideoAspectRatio(aspectRatio)
    }

    func setLandscape(_ landscape: Bool) {
        latestLayout?.usesLandscapeChrome = landscape
        appliedLayout?.usesLandscapeChrome = landscape
        host?.setLandscape(landscape)
    }

    func setPortraitFullscreen(_ active: Bool) {
        latestLayout?.usesPortraitFullscreen = active
        appliedLayout?.usesPortraitFullscreen = active
        host?.setPortraitFullscreen(active)
    }

    func setBareSurfaceTransitionActive(_ active: Bool, retainsChromeTree: Bool) {
        host?.setBareSurfaceTransitionActive(active, retainsChromeTree: retainsChromeTree)
    }

    func cancelRotationChromePrewarm() {
        rotationChromePrewarmCancellable = nil
        host?.cancelRotationChromePrewarm()
    }

    func refreshLayoutImmediately() {
        host?.refreshLayoutImmediately()
    }

    private func receiveActivePlayer(
        _ playerViewModel: PlayerStateViewModel?,
        from sessionID: ObjectIdentifier
    ) {
        guard playbackSessionID == sessionID else { return }
        guard let playerViewModel else {
            updateActivePlayer(nil)
            return
        }
        guard let layout = latestLayout else { return }
        bindActivePlayer(playerViewModel, layout: layout)
    }

    private func bindActivePlayer(
        _ playerViewModel: PlayerStateViewModel,
        layout: PlayerSurfaceLayout
    ) {
        let isNewPlayer = updateActivePlayer(playerViewModel)
        if let host {
            host.setPlayerViewModel(playerViewModel)
            updateLayout(layout)
            scheduleRotationChromePrewarm(for: playerViewModel)
            return
        }

        guard let parentViewController,
              let containerView,
              let host = makeHost(playerViewModel)
        else { return }
        host.attach(to: parentViewController)
        host.surfaceView.frame = containerView.bounds
        containerView.insertSubview(host.surfaceView, at: 0)
        self.host = host
        appliedLayout = nil
        updateLayout(layout)
        scheduleRotationChromePrewarm(for: playerViewModel)
        if isNewPlayer, playerViewModel.wantsAutoplay {
            playerViewModel.play()
        }
    }

    @discardableResult
    private func updateActivePlayer(_ playerViewModel: PlayerStateViewModel?) -> Bool {
        let nextPlayerID = playerViewModel.map(ObjectIdentifier.init)
        guard activePlayerID != nextPlayerID else { return false }
        activePlayerID = nextPlayerID
        onActivePlayerChange?(playerViewModel)
        return true
    }

    private func scheduleRotationChromePrewarm(for playerViewModel: PlayerStateViewModel) {
        let playerID = ObjectIdentifier(playerViewModel)
        guard rotationChromePrewarmedPlayerID != playerID else { return }
        rotationChromePrewarmedPlayerID = playerID
        rotationChromePrewarmCancellable = playerViewModel.$hasPresentedPlayback
            .removeDuplicates()
            .filter { $0 }
            .prefix(1)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak playerViewModel] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    guard let self,
                          let playerViewModel,
                          self.activePlayerID == ObjectIdentifier(playerViewModel)
                    else { return }
                    self.host?.prewarmRotationChrome()
                }
            }
    }
}
