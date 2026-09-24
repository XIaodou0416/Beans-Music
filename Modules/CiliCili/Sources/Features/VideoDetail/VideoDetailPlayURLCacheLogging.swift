import Foundation
import OSLog

extension VideoDetailViewModel {
    func logPlayURLCacheBypass(kind: String, data: PlayURLData) {
        PlayerMetricsLog.logger.info(
            "playURL\(kind)Bypass bvid=\(self.detail.bvid, privacy: .public) startupPreferred=\(self.adaptiveStartupPreferredQuality ?? 0, privacy: .public) targetPreferred=\(self.targetPlaybackPreferredQuality ?? 0, privacy: .public) cachedQualities=\(Self.qualitySummary(data.playVariants), privacy: .public)"
        )
    }
}
