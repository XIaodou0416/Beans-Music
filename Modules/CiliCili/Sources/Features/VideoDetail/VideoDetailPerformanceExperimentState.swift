import Combine
import Foundation

struct VideoDetailPerformanceExperimentSnapshot: Equatable {
    var directUIKitSurfaceEnabled = false
    var narrowPlayerOverlayObservationEnabled = false
    var isBareSurfaceTransitionActive = false
    var overlayPublishCount = 0
    var overlayDeferredCount = 0
    var overlayFlushCount = 0
    var playerStatePublishCount = 0
    var settingsStatePublishCount = 0
    var playerRebindCount = 0
    var rotationTransitionCount = 0
    var lastBareSurfaceDurationMilliseconds = 0
    var totalBareSurfaceDurationMilliseconds = 0
    var lastEvent = "运行中"

    nonisolated init(
        directUIKitSurfaceEnabled: Bool = false,
        narrowPlayerOverlayObservationEnabled: Bool = false,
        isBareSurfaceTransitionActive: Bool = false,
        overlayPublishCount: Int = 0,
        overlayDeferredCount: Int = 0,
        overlayFlushCount: Int = 0,
        playerStatePublishCount: Int = 0,
        settingsStatePublishCount: Int = 0,
        playerRebindCount: Int = 0,
        rotationTransitionCount: Int = 0,
        lastBareSurfaceDurationMilliseconds: Int = 0,
        totalBareSurfaceDurationMilliseconds: Int = 0,
        lastEvent: String = "运行中"
    ) {
        self.directUIKitSurfaceEnabled = directUIKitSurfaceEnabled
        self.narrowPlayerOverlayObservationEnabled = narrowPlayerOverlayObservationEnabled
        self.isBareSurfaceTransitionActive = isBareSurfaceTransitionActive
        self.overlayPublishCount = overlayPublishCount
        self.overlayDeferredCount = overlayDeferredCount
        self.overlayFlushCount = overlayFlushCount
        self.playerStatePublishCount = playerStatePublishCount
        self.settingsStatePublishCount = settingsStatePublishCount
        self.playerRebindCount = playerRebindCount
        self.rotationTransitionCount = rotationTransitionCount
        self.lastBareSurfaceDurationMilliseconds = lastBareSurfaceDurationMilliseconds
        self.totalBareSurfaceDurationMilliseconds = totalBareSurfaceDurationMilliseconds
        self.lastEvent = lastEvent
    }

}

@MainActor
final class VideoDetailPerformanceExperimentState: ObservableObject {
    @Published private(set) var snapshot: VideoDetailPerformanceExperimentSnapshot
    private var bareSurfaceTransitionBeganAt: Date?
    private var pendingPlayerStatePublishCount = 0
    private var pendingSettingsStatePublishCount = 0
    private var observationCountFlushTask: Task<Void, Never>?

    init(
        directUIKitSurfaceEnabled: Bool = false,
        narrowPlayerOverlayObservationEnabled: Bool = false
    ) {
        snapshot = VideoDetailPerformanceExperimentSnapshot(
            directUIKitSurfaceEnabled: directUIKitSurfaceEnabled,
            narrowPlayerOverlayObservationEnabled: narrowPlayerOverlayObservationEnabled
        )
    }

    func setBareSurfaceTransitionActive(_ active: Bool) {
        let now = Date()
        update { snapshot in
            guard snapshot.isBareSurfaceTransitionActive != active else { return }
            snapshot.isBareSurfaceTransitionActive = active
            if active {
                bareSurfaceTransitionBeganAt = now
                snapshot.rotationTransitionCount += 1
                snapshot.lastEvent = "旋转中：冻结叠层刷新"
            } else {
                let elapsedMilliseconds = bareSurfaceTransitionBeganAt
                    .map { max(0, Int((now.timeIntervalSince($0) * 1_000).rounded())) }
                    ?? 0
                bareSurfaceTransitionBeganAt = nil
                if elapsedMilliseconds > 0 {
                    snapshot.lastBareSurfaceDurationMilliseconds = elapsedMilliseconds
                    snapshot.totalBareSurfaceDurationMilliseconds += elapsedMilliseconds
                }
                snapshot.lastEvent = "旋转结束：恢复叠层刷新"
            }
        }
    }

    func recordOverlayPublish() {
        update { snapshot in
            snapshot.overlayPublishCount += 1
            snapshot.lastEvent = "叠层快照已发布"
        }
    }

    func recordOverlayDeferred() {
        update { snapshot in
            snapshot.overlayDeferredCount += 1
            snapshot.lastEvent = "旋转中暂存叠层更新"
        }
    }

    func recordOverlayFlush() {
        update { snapshot in
            snapshot.overlayFlushCount += 1
            snapshot.lastEvent = "恢复后合并发布叠层更新"
        }
    }

    func recordPlayerStatePublish() {
        guard snapshot.narrowPlayerOverlayObservationEnabled else { return }
        pendingPlayerStatePublishCount += 1
        scheduleObservationCountFlush()
    }

    func recordSettingsStatePublish() {
        guard snapshot.narrowPlayerOverlayObservationEnabled else { return }
        pendingSettingsStatePublishCount += 1
        scheduleObservationCountFlush()
    }

    func recordPlayerRebind() {
        guard snapshot.narrowPlayerOverlayObservationEnabled else { return }
        update { snapshot in
            snapshot.playerRebindCount += 1
            snapshot.lastEvent = "播放器已原位重绑"
        }
    }

    private func scheduleObservationCountFlush() {
        guard observationCountFlushTask == nil else { return }
        observationCountFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.observationCountFlushTask = nil
            self.flushObservationCounts()
        }
    }

    private func flushObservationCounts() {
        let playerCount = pendingPlayerStatePublishCount
        let settingsCount = pendingSettingsStatePublishCount
        pendingPlayerStatePublishCount = 0
        pendingSettingsStatePublishCount = 0
        guard playerCount > 0 || settingsCount > 0 else { return }
        update { snapshot in
            snapshot.playerStatePublishCount += playerCount
            snapshot.settingsStatePublishCount += settingsCount
        }
    }

    private func update(_ transform: (inout VideoDetailPerformanceExperimentSnapshot) -> Void) {
        var next = snapshot
        transform(&next)
        guard next != snapshot else { return }
        snapshot = next
    }

    deinit {
        observationCountFlushTask?.cancel()
    }
}
