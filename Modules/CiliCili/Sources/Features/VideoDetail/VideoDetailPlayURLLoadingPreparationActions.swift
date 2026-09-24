import Foundation
import QuartzCore

extension VideoDetailViewModel {
    func preparePlayURLLoading(mode: VideoDetailPlayURLLoadMode) {
        playURLState = .loading
        playURLLoadStartTime = CACurrentMediaTime()
        playURLElapsedMilliseconds = nil
        lastPlayURLSource = nil
        if mode == .playbackRecovery {
            cancelStartupPlayURLTask()
        }
        PlayerMetricsLog.record(.playURLStart, metricsID: detail.bvid, title: detail.title, message: mode.startMessage)
    }

    func failPlayURLLoadingForMissingCID() {
        pendingVideoListenPlaybackIntent = nil
        currentPlayURLData = nil
        clearVideoListenAudioVariants()
        playVariants = []
        selectedPlayVariant = nil
        playURLElapsedMilliseconds = elapsedMilliseconds(since: playURLLoadStartTime)
        playURLState = .failed("没有找到视频 CID，无法请求播放地址")
    }
}
