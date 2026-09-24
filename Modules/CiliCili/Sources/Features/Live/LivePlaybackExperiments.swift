import Combine
import CoreGraphics
import Foundation

nonisolated enum LivePlaybackPolicy {
    static let auxiliaryLoadDelayNanoseconds: UInt64 = 180_000_000
    static let danmakuRenderBatchWindowNanoseconds: UInt64 = 150_000_000
    static let knownUnhealthyHostWatchdogSeconds: TimeInterval = 4.5
    static let slowStartupThresholdMilliseconds = 2_200
    static let slowStartupRouteSwitchDelayMilliseconds = 2_200
    static let slowStartupRouteSwitchDelayNanoseconds: UInt64 =
        UInt64(slowStartupRouteSwitchDelayMilliseconds) * 1_000_000
}

/// Controls the formal live-rotation path. It keeps the player
/// surface, controls and danmaku tree alive, while temporarily hiding the chat
/// host so its SwiftUI layout work cannot contend with the system rotation.
nonisolated struct LiveRotationSurfaceStabilityPolicy: Equatable {

    func hidesContentHost(duringTransitionToLandscape _: Bool) -> Bool {
        // The host remains mounted either way. Hiding it through the full
        // transaction prevents the chat timeline from exposing its grouped
        // background or relaying a large layout pass into the rotation.
        return true
    }

    func allowsContentHostInteraction(duringTransitionToLandscape _: Bool) -> Bool {
        return false
    }

    func retainsChromeTree() -> Bool {
        true
    }

}

/// Direct live HLS starts with a short startup buffer until the first displayed
/// frame, then restores AVPlayer's normal steady-state buffering policy.
nonisolated enum LiveHLSFastStartPolicy {
    static func activatesForDirectLiveHLS(
        isDirectLiveHLS: Bool,
        isLiveStream: Bool
    ) -> Bool {
        isDirectLiveHLS && isLiveStream
    }

    static func usesImmediatePlayback(
        isDirectLiveHLS: Bool,
        isLiveStream: Bool,
        isStartupFastStartActive: Bool
    ) -> Bool {
        isStartupFastStartActive
            && activatesForDirectLiveHLS(
                isDirectLiveHLS: isDirectLiveHLS,
                isLiveStream: isLiveStream
            )
    }

    /// A TS playlist has no partial segments. Starting at the exact live edge
    /// can therefore make AVPlayer wait for the next segment before rendering
    /// anything. Let its native HLS start position choose a completed segment
    /// for the first frame; the explicit refresh control still seeks to edge.
    static func defersInitialLiveEdgeSeek(streamFormat: String?) -> Bool {
        streamFormat?.localizedCaseInsensitiveContains("ts") == true
    }
}

/// Transport-stream HLS can spend several seconds waiting for a segment
/// boundary. Do not compete with that first segment while startup auxiliary
/// work is waiting to begin.
nonisolated enum LiveStartupAuxiliaryPolicy {
    static func defersUntilFirstFrame(streamFormat: String?) -> Bool {
        return streamFormat?.localizedCaseInsensitiveContains("ts") == true
    }
}

/// 直播页的全屏目标由真实画面方向决定。未知和方形流维持嵌入态，避免
/// 在没有可靠尺寸前错误请求系统旋转。
nonisolated enum LiveRoomFullscreenMode: Equatable {
    case unavailable
    case portrait
    case landscape
}

nonisolated enum LiveRoomVideoDetailLayoutPolicy {
    static let landscapeAspectRatioThreshold: CGFloat = 1.0
    static let portraitAspectRatioThreshold: CGFloat = 0.9

    static func fullscreenMode(videoAspectRatio: CGFloat?) -> LiveRoomFullscreenMode {
        guard let videoAspectRatio,
              videoAspectRatio.isFinite,
              videoAspectRatio > 0.1
        else {
            return .unavailable
        }

        if videoAspectRatio > landscapeAspectRatioThreshold {
            return .landscape
        }
        if videoAspectRatio < portraitAspectRatioThreshold {
            return .portrait
        }
        return .unavailable
    }

    static func supportsFullscreen(videoAspectRatio: CGFloat?) -> Bool {
        fullscreenMode(videoAspectRatio: videoAspectRatio) != .unavailable
    }

    static func supportsPortraitFullscreen(videoAspectRatio: CGFloat?) -> Bool {
        fullscreenMode(videoAspectRatio: videoAspectRatio) == .portrait
    }

    static func usesLandscapeFullscreen(
        isLandscape: Bool,
        videoAspectRatio: CGFloat?
    ) -> Bool {
        isLandscape && fullscreenMode(videoAspectRatio: videoAspectRatio) == .landscape
    }

    static func supportsLandscapeFullscreen(videoAspectRatio: CGFloat?) -> Bool {
        fullscreenMode(videoAspectRatio: videoAspectRatio) == .landscape
    }
}

/// SimpleLive 风格直播页在竖屏同时展示主播栏、播放器、分段内容和底部操作栏。
/// 播放器不能只按屏幕宽度撑开，否则竖向源或较矮设备会挤掉内容和安全区。
nonisolated enum LiveRoomSimpleLiveLayoutPolicy {
    static let headerContentHeight: CGFloat = 58
    static let playerMaximumAspectRatio: CGFloat = 4.0 / 3.0
    static let minimumDetailHeight: CGFloat = 286

    static func playerHeight(
        containerSize: CGSize,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat,
        videoAspectRatio: CGFloat?
    ) -> CGFloat {
        guard containerSize.width > 0, containerSize.height > 0 else { return 0 }

        let aspectRatio = max(videoAspectRatio ?? 16.0 / 9.0, 0.1)
        let preferredHeight = min(
            containerSize.width / aspectRatio,
            containerSize.width * playerMaximumAspectRatio
        )
        let availableHeight = max(
            0,
            containerSize.height
                - max(safeAreaTop, 0)
                - max(safeAreaBottom, 0)
                - headerContentHeight
                - max(minimumDetailHeight, 0)
        )
        return min(preferredHeight, availableHeight).rounded(.down)
    }
}

struct LiveRotationSurfaceAlignmentSnapshot: Equatable {
    var isBareSurfaceTransitionActive = false
    var overlayDeferredCount = 0
    var overlayFlushCount = 0
    var chatDeferredCount = 0
    var chatFlushCount = 0
    var rotationTransitionCount = 0
    var lastBareSurfaceDurationMilliseconds = 0
    var totalBareSurfaceDurationMilliseconds = 0
    var presentationWidth: Int?
    var presentationHeight: Int?
    var videoAspectRatio: CGFloat?
    var lastEvent = "运行中"

    var presentationSizeText: String {
        guard let presentationWidth, let presentationHeight else { return "-" }
        return "\(presentationWidth)x\(presentationHeight)"
    }
}

@MainActor
final class LiveRotationSurfaceAlignmentState: ObservableObject {
    @Published private(set) var snapshot = LiveRotationSurfaceAlignmentSnapshot()
    private var bareSurfaceTransitionBeganAt: Date?

    func setBareSurfaceTransitionActive(_ active: Bool) {
        let now = Date()
        update { snapshot in
            guard snapshot.isBareSurfaceTransitionActive != active else { return }
            snapshot.isBareSurfaceTransitionActive = active
            if active {
                bareSurfaceTransitionBeganAt = now
                snapshot.rotationTransitionCount += 1
                snapshot.lastEvent = "旋转中：暂存直播叠层更新"
            } else {
                let elapsedMilliseconds = bareSurfaceTransitionBeganAt
                    .map { max(0, Int((now.timeIntervalSince($0) * 1_000).rounded())) }
                    ?? 0
                bareSurfaceTransitionBeganAt = nil
                if elapsedMilliseconds > 0 {
                    snapshot.lastBareSurfaceDurationMilliseconds = elapsedMilliseconds
                    snapshot.totalBareSurfaceDurationMilliseconds += elapsedMilliseconds
                }
                snapshot.lastEvent = "旋转结束：恢复直播叠层更新"
            }
        }
    }

    func recordOverlayDeferred() {
        update { snapshot in
            snapshot.overlayDeferredCount += 1
            snapshot.lastEvent = "旋转中暂存屏幕弹幕"
        }
    }

    func recordOverlayFlush() {
        update { snapshot in
            snapshot.overlayFlushCount += 1
            snapshot.lastEvent = "旋转后合并刷新屏幕弹幕"
        }
    }

    func recordChatDeferred() {
        update { snapshot in
            snapshot.chatDeferredCount += 1
            snapshot.lastEvent = "旋转中暂存聊天列表"
        }
    }

    func recordChatFlush() {
        update { snapshot in
            snapshot.chatFlushCount += 1
            snapshot.lastEvent = "旋转后合并刷新聊天列表"
        }
    }

    func updatePresentationSize(_ size: CGSize) {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let isUsable = width > 0 && height > 0
        let aspectRatio = isUsable ? CGFloat(width) / CGFloat(height) : nil
        update { snapshot in
            let nextWidth = isUsable ? width : nil
            let nextHeight = isUsable ? height : nil
            guard snapshot.presentationWidth != nextWidth
                    || snapshot.presentationHeight != nextHeight
                    || snapshot.videoAspectRatio != aspectRatio
            else { return }
            snapshot.presentationWidth = nextWidth
            snapshot.presentationHeight = nextHeight
            snapshot.videoAspectRatio = aspectRatio
            snapshot.lastEvent = isUsable ? "已更新直播真实画幅" : "等待直播真实画幅"
        }
    }

    private func update(_ transform: (inout LiveRotationSurfaceAlignmentSnapshot) -> Void) {
        var next = snapshot
        transform(&next)
        guard next != snapshot else { return }
        snapshot = next
    }
}

/// A bounded fallback plan for transport-stream live HLS. It only considers
/// official, equivalent alternatives from the same playurl response.
nonisolated struct LiveSlowStartupRouteSwitchPlan: Equatable {
    let primaryIndex: Int
    let fallbackIndex: Int

    static func make(
        candidates: [LiveStreamURLCandidate],
        primaryIndex: Int
    ) -> LiveSlowStartupRouteSwitchPlan? {
        guard candidates.indices.contains(primaryIndex) else { return nil }
        let primary = candidates[primaryIndex]
        guard primary.isTransportStreamHLS,
              let primaryHost = primary.normalizedStartupHost
        else {
            return nil
        }

        let profile = LiveStreamStartupProfile(primary)
        guard let fallbackIndex = candidates.indices.first(where: { index in
            guard index != primaryIndex else { return false }
            let candidate = candidates[index]
            return candidate.isTransportStreamHLS
                && LiveStreamStartupProfile(candidate) == profile
                && candidate.normalizedStartupHost != primaryHost
        }) else {
            return nil
        }
        return LiveSlowStartupRouteSwitchPlan(
            primaryIndex: primaryIndex,
            fallbackIndex: fallbackIndex
        )
    }
}

nonisolated struct LiveStreamStartupHealthSnapshot: Equatable {
    let recentFirstFrameMilliseconds: Int?
    let slowStartCount: Int
    let failureCount: Int

    var diagnosticsTitle: String {
        var values = [String]()
        if let recentFirstFrameMilliseconds {
            values.append("最近首帧 \(recentFirstFrameMilliseconds)ms")
        }
        if slowStartCount > 0 {
            values.append("慢启动 \(slowStartCount) 次")
        }
        if failureCount > 0 {
            values.append("失败 \(failureCount) 次")
        }
        return values.isEmpty ? "暂无记录" : values.joined(separator: " · ")
    }
}

nonisolated struct LiveStreamStartupProfile: Hashable {
    let source: String
    let protocolName: String?
    let formatName: String?
    let codecName: String?
    let quality: Int?

    init(_ candidate: LiveStreamURLCandidate) {
        source = candidate.source
        protocolName = candidate.protocolName
        formatName = candidate.formatName
        codecName = candidate.codecName
        quality = candidate.currentQN
    }
}

/// Ephemeral health observations for server-provided live stream hosts.
/// The policy never rewrites a URL; it only reorders equivalent URLs that
/// Bilibili already supplied for the current stream profile.
@MainActor
final class LiveStreamStartupHealthMemory {
    static let shared = LiveStreamStartupHealthMemory()

    private struct RouteKey: Hashable {
        let host: String
        let profile: LiveStreamStartupProfile
    }

    private struct HostHealth {
        var consecutiveFailures: Int
        var slowStartCount: Int
        var lastFailure: Date
        var lastSlowStart: Date?
        var lastFirstFrameMilliseconds: Int?
    }

    private let healthLifetime: TimeInterval = 10 * 60
    private var healthByRoute = [RouteKey: HostHealth]()

    func orderedStartupCandidates(_ candidates: [LiveStreamURLCandidate]) -> [LiveStreamURLCandidate] {
        guard candidates.count > 1 else { return candidates }
        let now = Date()
        purgeExpiredHealth(now: now)

        let indexedCandidates: [(offset: Int, candidate: LiveStreamURLCandidate)] =
            candidates.enumerated().map { offset, candidate in
                (offset: offset, candidate: candidate)
            }

        var ordered = candidates
        let candidatesByProfile = Dictionary(grouping: indexedCandidates) {
            LiveStreamStartupProfile($0.candidate)
        }
        for group in candidatesByProfile.values {
            guard group.count > 1 else { continue }
            let originalOrder = group.sorted { $0.offset < $1.offset }
            let rankedCandidates = originalOrder
                .sorted(by: { lhs, rhs in
                    let lhsRank = healthRank(for: lhs.candidate, now: now)
                    let rhsRank = healthRank(for: rhs.candidate, now: now)
                    if lhsRank != rhsRank {
                        return lhsRank < rhsRank
                    }
                    return lhs.offset < rhs.offset
                })
                .map(\.candidate)
            for (entry, candidate) in zip(originalOrder, rankedCandidates) {
                ordered[entry.offset] = candidate
            }
        }
        return ordered
    }

    func recordStartupFailure(for candidate: LiveStreamURLCandidate) {
        guard let key = routeKey(for: candidate) else { return }
        let now = Date()
        purgeExpiredHealth(now: now)
        let existing = healthByRoute[key]
        healthByRoute[key] = HostHealth(
            consecutiveFailures: min((existing?.consecutiveFailures ?? 0) + 1, 3),
            slowStartCount: existing?.slowStartCount ?? 0,
            lastFailure: now,
            lastSlowStart: existing?.lastSlowStart,
            lastFirstFrameMilliseconds: existing?.lastFirstFrameMilliseconds
        )
    }

    func recordStartupSuccess(for candidate: LiveStreamURLCandidate) {
        guard let key = routeKey(for: candidate), var health = healthByRoute[key] else { return }
        health.consecutiveFailures = 0
        if health.slowStartCount == 0 {
            healthByRoute[key] = nil
        } else {
            healthByRoute[key] = health
        }
    }

    func recordStartupResult(
        for candidate: LiveStreamURLCandidate,
        firstFrameMilliseconds: Int
    ) {
        guard firstFrameMilliseconds >= 0, let key = routeKey(for: candidate) else { return }
        let now = Date()
        purgeExpiredHealth(now: now)
        var health = healthByRoute[key] ?? HostHealth(
            consecutiveFailures: 0,
            slowStartCount: 0,
            lastFailure: now,
            lastSlowStart: nil,
            lastFirstFrameMilliseconds: nil
        )
        health.consecutiveFailures = 0
        health.lastFirstFrameMilliseconds = firstFrameMilliseconds

        if firstFrameMilliseconds >= LivePlaybackPolicy.slowStartupThresholdMilliseconds {
            let isSameAttempt = health.lastSlowStart.map { now.timeIntervalSince($0) < 10 } ?? false
            if !isSameAttempt {
                health.slowStartCount = min(health.slowStartCount + 1, 3)
            }
            health.lastSlowStart = now
        } else if health.slowStartCount > 0 {
            health.slowStartCount -= 1
            if health.slowStartCount == 0 {
                health.lastSlowStart = nil
            }
        }

        if health.consecutiveFailures == 0, health.slowStartCount == 0 {
            healthByRoute[key] = nil
        } else {
            healthByRoute[key] = health
        }
    }

    func snapshot(for candidate: LiveStreamURLCandidate) -> LiveStreamStartupHealthSnapshot? {
        let now = Date()
        purgeExpiredHealth(now: now)
        guard let key = routeKey(for: candidate), let health = healthByRoute[key] else {
            return nil
        }
        return LiveStreamStartupHealthSnapshot(
            recentFirstFrameMilliseconds: health.lastFirstFrameMilliseconds,
            slowStartCount: health.slowStartCount,
            failureCount: health.consecutiveFailures
        )
    }

    func hasRecentFailure(for candidate: LiveStreamURLCandidate) -> Bool {
        let now = Date()
        purgeExpiredHealth(now: now)
        guard let key = routeKey(for: candidate),
              let health = healthByRoute[key]
        else {
            return false
        }
        return health.consecutiveFailures > 0
    }

    func reset() {
        healthByRoute.removeAll()
    }

    private func healthRank(for candidate: LiveStreamURLCandidate, now: Date) -> Int {
        guard let key = routeKey(for: candidate),
              let health = healthByRoute[key],
              now.timeIntervalSince(health.lastFailure) < healthLifetime
        else {
            return 0
        }
        return health.consecutiveFailures * 10 + health.slowStartCount * 2
    }

    private func routeKey(for candidate: LiveStreamURLCandidate) -> RouteKey? {
        guard let host = candidate.normalizedStartupHost else { return nil }
        return RouteKey(host: host, profile: LiveStreamStartupProfile(candidate))
    }

    private func purgeExpiredHealth(now: Date) {
        healthByRoute = healthByRoute.filter {
            now.timeIntervalSince($0.value.lastFailure) < healthLifetime
                || $0.value.lastSlowStart.map { now.timeIntervalSince($0) < healthLifetime } == true
        }
    }
}

nonisolated private extension LiveStreamURLCandidate {
    var normalizedStartupHost: String? {
        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return host.isEmpty ? nil : host
    }

    var isTransportStreamHLS: Bool {
        isLikelyHLS && formatName?.localizedCaseInsensitiveContains("ts") == true
    }
}
