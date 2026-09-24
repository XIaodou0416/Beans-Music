import Foundation

enum PlaybackNetworkDiagnosticsProbeAction {
    struct Result: Sendable {
        let snapshot: PlaybackCDNProbeSnapshot
        let recommendedPreference: PlaybackCDNPreference?
        let message: String
    }

    static func run(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference,
        playbackURLs: [URL]
    ) async -> Result {
        let snapshot = await PlaybackCDNProbeService.recommendedSnapshot(
            addressFamilyPreference: addressFamilyPreference,
            playbackURLs: playbackURLs
        )
        if snapshot.isWeakReferenceOnly {
            return Result(
                snapshot: snapshot,
                recommendedPreference: nil,
                message: "没有当前播放地址，本次只做 Host 弱参考；403/959 不代表真实播放失败。"
            )
        }
        if let preference = snapshot.recommendedPreference,
           let elapsed = snapshot.result(for: preference)?.elapsedMilliseconds {
            return Result(
                snapshot: snapshot,
                recommendedPreference: preference,
                message: "已推荐 \(preference.title)，\(elapsed) ms"
            )
        }
        return Result(
            snapshot: snapshot,
            recommendedPreference: nil,
            message: "未找到可用 CDN，已保留当前设置"
        )
    }
}
