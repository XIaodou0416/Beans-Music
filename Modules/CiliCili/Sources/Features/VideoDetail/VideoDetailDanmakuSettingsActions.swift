import Foundation

extension VideoDetailViewModel {
    func toggleDanmaku() {
        isDanmakuEnabled.toggle()
        libraryStore.setDanmakuEnabled(isDanmakuEnabled)
        if isDanmakuEnabled, danmakuItems.isEmpty {
            scheduleDanmakuLoadIfNeeded()
        } else if !isDanmakuEnabled {
            resetDanmakuLoad(clearItems: false)
        }
    }

    func updateDanmakuSettings(_ settings: DanmakuSettings) {
        let normalizedSettings = settings.normalized
        danmakuSettings = normalizedSettings
        libraryStore.setDanmakuSettings(normalizedSettings)
    }

    var effectiveDanmakuSettings: DanmakuSettings {
        var settings = danmakuSettings
        settings.loadFactor = libraryStore.isPlaybackAutoOptimizationEnabled
            ? playbackAdaptationProfile.danmakuLoadFactor
            : 1.0
        return settings.normalized
    }
}
