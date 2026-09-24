import Foundation

extension PlaybackNetworkProbeSection {
    var playbackCDNProbeRefreshIntervalTitle: String {
        let minutes = libraryStore.playbackCDNProbeRefreshIntervalMinutes
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60) 小时"
        }
        return "\(minutes) 分钟"
    }

    func isPlaybackCDNProbeSnapshotExpired(_ snapshot: PlaybackCDNProbeSnapshot) -> Bool {
        snapshot.isExpired(freshnessInterval: libraryStore.playbackCDNProbeRefreshInterval)
    }
}
