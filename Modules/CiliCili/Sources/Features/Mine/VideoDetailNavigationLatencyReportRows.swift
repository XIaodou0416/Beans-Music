import SwiftUI

struct VideoDetailNavigationLatencySnapshotRow: View {
    let snapshot: PlaybackDetailPerformanceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(snapshot.context.title ?? snapshot.context.mediaID)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Text(snapshot.navigationExperimentSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(reportEvents.enumerated()), id: \.offset) { _, event in
                HStack(spacing: 8) {
                    Text(event.milestone.navigationReportTitle)
                    Spacer(minLength: 8)
                    let timing = VideoDetailNavigationLatencyTiming.presentation(
                        for: event,
                        in: snapshot
                    )
                    Text(timing.displayText)
                        .foregroundStyle(timing.isSlow ? .orange : .secondary)
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(.vertical, 3)
    }

    private var reportEvents: [PlaybackDetailPerformanceEventRecord] {
        snapshot.events.filter { $0.milestone.isNavigationReportMilestone }
    }
}

enum VideoDetailNavigationLatencyReportFormatter {
    static func copyText(_ snapshots: [PlaybackDetailPerformanceSnapshot]) -> String {
        guard !snapshots.isEmpty else { return "" }
        return (["[视频详情导航时延]"] + snapshots.flatMap(snapshotLines)).joined(
            separator: "\n"
        )
    }

    private static func snapshotLines(
        _ snapshot: PlaybackDetailPerformanceSnapshot
    ) -> [String] {
        let title = snapshot.context.title ?? snapshot.context.mediaID
        let group = snapshot.navigationExperimentGroupTitle.map { " group=\($0)" } ?? ""
        let header = "\n\(title) total=\(snapshot.durationMilliseconds)ms\(group)"
        let events = snapshot.events.compactMap { event -> String? in
            guard event.milestone.isNavigationReportMilestone else { return nil }
            let timing = VideoDetailNavigationLatencyTiming.presentation(
                for: event,
                in: snapshot
            )
            let slow = timing.isSlow ? " slow" : ""
            let detail = event.detail.map { " \($0)" } ?? ""
            return
                "\(event.milestone.rawValue) \(timing.copyText) elapsed=\(event.elapsedMilliseconds)ms\(slow)\(detail)"
        }
        return [header] + events
    }
}

private enum VideoDetailNavigationLatencyTiming {
    struct Presentation {
        let displayText: String
        let copyText: String
        let durationMilliseconds: Int?
        let milestone: PlaybackDetailPerformanceMilestone
        let isLatency: Bool

        var isSlow: Bool {
            guard isLatency, let durationMilliseconds else { return false }
            return durationMilliseconds >= milestone.navigationSlowThresholdMilliseconds
        }
    }

    static func presentation(
        for event: PlaybackDetailPerformanceEventRecord,
        in snapshot: PlaybackDetailPerformanceSnapshot
    ) -> Presentation {
        switch event.milestone {
        case .navigationRequested:
            return make(event, display: "进入 0ms", copy: "phase=0ms", duration: 0, isLatency: true)
        case .navigationBackRequested:
            return make(event, display: "用户操作", copy: "action", duration: nil, isLatency: false)
        case .returnedPageVisible:
            guard let duration = backToVisibleMilliseconds(from: event.detail) else {
                return make(
                    event,
                    display: "返回耗时未知",
                    copy: "back=unknown",
                    duration: nil,
                    isLatency: false
                )
            }
            return make(
                event,
                display: "返回 \(duration)ms",
                copy: "back=\(duration)ms",
                duration: duration,
                isLatency: true
            )
        case .pageDisappeared:
            if let disappearIndex = snapshot.events.lastIndex(of: event),
                let backRequestIndex = snapshot.events[..<disappearIndex].lastIndex(where: {
                    $0.milestone == .navigationBackRequested
                })
            {
                let backRequest = snapshot.events[backRequestIndex]
                let backRequestWasConsumed = snapshot.events[
                    (backRequestIndex + 1)..<disappearIndex
                ].contains {
                    $0.milestone == .returnedPageVisible
                }
                if !backRequestWasConsumed {
                    let duration = max(
                        event.elapsedMilliseconds - backRequest.elapsedMilliseconds,
                        0
                    )
                    return make(
                        event,
                        display: "返回 \(duration)ms",
                        copy: "back=\(duration)ms",
                        duration: duration,
                        isLatency: true
                    )
                }
            }
            return make(
                event,
                display: "停留 \(event.deltaMilliseconds)ms",
                copy: "dwell=\(event.deltaMilliseconds)ms",
                duration: event.deltaMilliseconds,
                isLatency: false
            )
        case .backgroundRenderFreezeReleased:
            guard
                let returnBoundary = snapshot.events.last(where: {
                    ($0.milestone == .returnedPageVisible
                        || $0.milestone == .navigationBackRequested)
                        && $0.elapsedMilliseconds <= event.elapsedMilliseconds
                })
            else {
                return make(
                    event,
                    display: "恢复耗时未知",
                    copy: "resume=unknown",
                    duration: nil,
                    isLatency: false
                )
            }
            let duration = max(event.elapsedMilliseconds - returnBoundary.elapsedMilliseconds, 0)
            return make(
                event,
                display: "恢复 \(duration)ms",
                copy: "resume=\(duration)ms",
                duration: duration,
                isLatency: true
            )
        default:
            guard
                let navigationStart = snapshot.events.first(where: {
                    $0.milestone == .navigationRequested
                })
            else {
                return make(
                    event,
                    display: "+\(event.deltaMilliseconds)ms",
                    copy: "delta=\(event.deltaMilliseconds)ms",
                    duration: event.deltaMilliseconds,
                    isLatency: false
                )
            }
            let duration = max(event.elapsedMilliseconds - navigationStart.elapsedMilliseconds, 0)
            return make(
                event,
                display: "进入 \(duration)ms",
                copy: "phase=\(duration)ms",
                duration: duration,
                isLatency: true
            )
        }
    }

    private static func make(
        _ event: PlaybackDetailPerformanceEventRecord,
        display: String,
        copy: String,
        duration: Int?,
        isLatency: Bool
    ) -> Presentation {
        Presentation(
            displayText: display,
            copyText: copy,
            durationMilliseconds: duration,
            milestone: event.milestone,
            isLatency: isLatency
        )
    }

    private static func backToVisibleMilliseconds(from detail: String?) -> Int? {
        guard
            let value = detail?.split(separator: " ").first(where: {
                $0.hasPrefix("backToVisible=")
            })
        else { return nil }
        return Int(value.dropFirst("backToVisible=".count).dropLast(2))
    }
}

extension PlaybackDetailPerformanceSnapshot {
    fileprivate var navigationExperimentSummary: String {
        if let navigationExperimentGroupTitle {
            return "\(navigationExperimentGroupTitle) · 总计 \(durationMilliseconds)ms"
        }
        return "总计 \(durationMilliseconds)ms"
    }

    fileprivate var navigationExperimentGroupTitle: String? {
        guard let detail = events.first(where: { $0.milestone == .navigationRequested })?.detail,
            let group = detail.split(separator: " ").first(where: { $0.hasPrefix("group=") })
        else {
            return nil
        }
        switch group.dropFirst("group=".count) {
        case "baseline":
            return "基线"
        case "experiment":
            return "实验组"
        case "formal":
            return "正式策略"
        case "custom":
            return "自定义"
        default:
            return nil
        }
    }
}

extension PlaybackDetailPerformanceMilestone {
    fileprivate var isNavigationReportMilestone: Bool {
        switch self {
        case .navigationRequested, .viewControllerLoaded, .pageAppeared,
            .viewControllerAppeared, .loadedContentAppeared, .playerAttached,
            .firstFramePresented, .navigationBackRequested, .returnedPageVisible,
            .backgroundRenderFreezeReleased, .pageDisappeared:
            return true
        case .initialContentAppeared, .initialContentRemoved,
            .fullscreenTransitionStarted, .fullscreenLayoutUpdated:
            return false
        }
    }

    fileprivate var navigationReportTitle: String {
        switch self {
        case .navigationRequested: "请求进入"
        case .viewControllerLoaded: "控制器加载"
        case .pageAppeared: "页面出现"
        case .viewControllerAppeared: "转场完成"
        case .initialContentAppeared: "占位内容"
        case .loadedContentAppeared: "详情内容"
        case .initialContentRemoved: "移除占位"
        case .playerAttached: "播放器挂载"
        case .firstFramePresented: "视频首帧"
        case .navigationBackRequested: "请求返回"
        case .returnedPageVisible: "上页可见"
        case .backgroundRenderFreezeReleased: "恢复后台页"
        case .fullscreenTransitionStarted: "全屏开始"
        case .fullscreenLayoutUpdated: "全屏布局"
        case .pageDisappeared: "页面消失"
        }
    }

    fileprivate var navigationSlowThresholdMilliseconds: Int {
        switch self {
        case .viewControllerLoaded, .pageAppeared, .loadedContentAppeared:
            return 120
        case .viewControllerAppeared, .returnedPageVisible,
            .backgroundRenderFreezeReleased, .pageDisappeared:
            return 750
        case .playerAttached:
            return 1_200
        case .firstFramePresented:
            return 2_000
        case .navigationRequested, .navigationBackRequested,
            .initialContentAppeared, .initialContentRemoved,
            .fullscreenTransitionStarted, .fullscreenLayoutUpdated:
            return .max
        }
    }
}
