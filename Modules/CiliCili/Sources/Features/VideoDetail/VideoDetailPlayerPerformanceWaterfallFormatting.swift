import Foundation

extension PlayerPerformanceOverlayFormatting {
    static func startupWaterfallStages(for session: PlayerPerformanceSession) -> [StartupWaterfallStage] {
        var stages: [StartupWaterfallStage] = []
        appendStartupStage(&stages, id: "open-detail", title: "打开", start: session.openedAt, end: session.detailStartedAt)
        appendStartupStage(&stages, id: "detail-url", title: "详情", start: session.detailStartedAt, end: session.playURLStartedAt)
        appendStartupStage(&stages, id: "url-load", title: "取流", start: session.playURLStartedAt, end: session.playURLLoadedAt)
        appendStartupStage(&stages, id: "player", title: "建播放器", start: session.playURLLoadedAt, end: session.playerCreatedAt)
        appendStartupStage(&stages, id: "prepare", title: "准备", start: session.prepareStartedAt, end: session.prepareReturnedAt)
        appendStartupStage(&stages, id: "first-frame", title: "首帧", start: session.playRequestedAt, end: session.firstFrameAt)
        return stages
    }

    private static func appendStartupStage(
        _ stages: inout [StartupWaterfallStage],
        id: String,
        title: String,
        start: Date?,
        end: Date?
    ) {
        guard let start, let end else { return }
        stages.append(StartupWaterfallStage(id: id, title: title, start: start, end: end))
    }
}
