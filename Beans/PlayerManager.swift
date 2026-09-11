import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

enum PlayMode: String, CaseIterable, Identifiable {
    case sequential
    case repeatOne
    case shuffle

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sequential: return "repeat"
        case .repeatOne: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }

    var title: String {
        switch self {
        case .sequential: return "顺序播放"
        case .repeatOne: return "单曲循环"
        case .shuffle: return "随机播放"
        }
    }
}

final class PlaybackClock: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var duration: Double = 0

    func update(progress: Double? = nil, duration: Double? = nil) {
        let apply = {
            if let progress, abs(progress - self.progress) > 0.01 {
                self.progress = progress
            }
            if let duration, abs(duration - self.duration) > 0.01 {
                self.duration = duration
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
}

final class PlayerManager: NSObject, ObservableObject {
    @Published var queue: [Song] = []
    @Published var currentIndex = 0
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var loadFailed = false
    /// 切歌代次：防止旧歌的 URL 解析任务覆盖新歌（快速切歌时）
    private var loadGeneration = 0
    let clock = PlaybackClock()
    var progress: Double = 0 {
        didSet { clock.update(progress: progress) }
    }
    var duration: Double = 0 {
        didSet { clock.update(duration: duration) }
    }
    @Published var playMode: PlayMode = .sequential {
        didSet {
            guard oldValue != playMode else { return }
            defaults.set(playMode.rawValue, forKey: playModeKey)
        }
    }
    @Published var rate: Double = 1.0
    @Published var sleepTimerEndsAt: Date?
    @Published var sleepTimerRemaining: Int = 0
    @Published var history: [Song] = []
    @Published var playCounts: [String: Int] = [:]
    /// 每次用户主动拖动进度或点击歌词都会递增，歌词视图据此立即重新定位。
    @Published private(set) var seekRevision = 0
    /// 歌词统一使用的播放游标，和播放器时间观察器使用同一个时间源。
    /// 高频游标不再触发整个播放器模型发布，由 PlaybackClock 驱动进度条与歌词局部刷新。
    private(set) var lyricProgress: Double = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var equalizerSettingsObserver: NSObjectProtocol?
    private var backendBlockObserver: NSObjectProtocol?
    private var playbackConfirmed = false
    private var pendingThirdPartyVIPNotice: ThirdPartyVIPNotice?
    private var sessionConfigured = false
    private var systemPlaybackPrepared = false
    private var routeObserverInstalled = false
    private var interruptionObserverInstalled = false
    private var secondaryAudioHintObserverInstalled = false
    private var mediaServicesObserverInstalled = false
    private var applicationAudioObserverInstalled = false
    private var remoteCommandsInstalled = false
    private var playOrder: [Int] = []
    private var orderPosition = 0
    private var sleepTimer: Timer?
    private var lastCountedSongID: String?
    private var wasPlayingBeforeInterruption = false
    private var interruptionInProgress = false
    private var interruptionResumeWorkItem: DispatchWorkItem?
    private var audioRecoveryWorkItem: DispatchWorkItem?
    private var audioSessionWatchdogTimer: Timer?
    private var shouldResumeAfterAudioLoss = false
    private var audioLossInProgress = false
    private var lastNowPlayingRefreshUptime = 0.0
    private var lastPublishedProgress: Double = -1
    private var lastPersistedProgress: Double = -1
    private var lastNowPlayingArtworkKey: String?
    private var nowPlayingSongKey: String?
    private var nowPlayingInfo: [String: Any] = [:]
    /// 酷狗高音质地址在部分账号/系统上会返回但无法由 AVPlayer 打开；每首歌只自动降级一次。
    private var kugouStandardFallbackSongKey: String?
    /// 第三方地址偶发过期或节点不可用时，按失败域名重试，避免同一节点反复进入播放器。
    private var thirdPartyRetryExcludedHostsBySong: [String: Set<String>] = [:]
    /// 记录已经交给 AVPlayer 的第三方音质，失败后选择下一个更低档位。
    private var attemptedThirdPartyQualitiesBySong: [String: Set<String>] = [:]
    private var activeThirdPartyQuality: ThirdPartyAudioQuality?
    /// 记录 QQ 官方 vkey 已经尝试过的 BR，官方地址实际打不开时继续换档位。
    private var attemptedQQOfficialBRsBySong: [String: Set<String>] = [:]
    private var activeQQOfficialBR: String?
    /// KVO 与 AVPlayerItemFailedToPlayToEndTime 可能同时报告同一次失败。
    private var playbackRecoveryInFlightSongKey: String?
    /// 同一首歌的多个 AVFoundation 失败回调只允许弹一次提示并自动切歌一次。
    private var finalizedFailureSongKey: String?
    /// 播放失败后安排到下一个主线程周期切歌，避免 AVFoundation 回调中同步重入。
    private var failureAutoSkipWorkItem: DispatchWorkItem?
    /// QQ 官方地址返回成功但实际不可播放时，只切换到第三方一次，避免官方/第三方之间循环。
    private var qqThirdPartyFallbackSongKey: String?
    private var playbackConfirmationWorkItem: DispatchWorkItem?
    private var playbackStallWorkItem: DispatchWorkItem?
    /// 提前解析下一首第三方地址，切歌时直接命中 UnblockService 的短缓存。
    private var thirdPartyPrefetchTask: Task<Void, Never>?
    private static let nowPlayingArtworkCache = NSCache<NSURL, UIImage>()

    private let historyKey = "beans.history"
    private let countsKey = "beans.playcounts"
    private let playbackStateKey = "beans.player.playbackState.v1"
    private let audioMixKey = "beans.audio.mixothers.v1"
    private let nowPlayingEnabledKey = "beans.nowPlaying.enabled.v1"
    private let playModeKey = "beans.player.playMode"
    private let autoSkipOnFailureKey = "beans.playback.autoSkipOnFailure"
    private let autoResumeLastPlaybackKey = "beans.playback.autoResumeLast"
    private let thirdPartyVIPNoticeKey = "beans.showThirdPartyVIPNotice"
    private let defaults = UserDefaults.standard
    private var didAttemptAutoResume = false

    /// 只要存在启用的自定义音源，就允许官方地址失败后进行兜底解析。
    private var externalSourcesEnabled: Bool {
        UnblockSourceStore.shared.sources.contains(where: \.enabled)
    }

    private struct ThirdPartyVIPNotice {
        let songKey: String
        let message: String
    }

    private enum PlaybackFailureCategory {
        case membership
        case network
        case sourceUnavailable
        case unsupportedFormat
        case thirdPartyUnavailable
        case unknown
    }

    private struct PersistedPlaybackState: Codable {
        let queue: [Song]
        let currentIndex: Int
        let progress: Double
        let duration: Double
        let savedAt: Date
    }

    var currentSong: Song? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    override init() {
        super.init()
        if let raw = defaults.string(forKey: playModeKey),
           let saved = PlayMode(rawValue: raw) {
            playMode = saved
        }
        loadHistory()
        loadPlayCounts()
        restorePersistedPlaybackState()
        equalizerSettingsObserver = NotificationCenter.default.addObserver(
            forName: BeansEqualizer.settingsDidChange,
            object: BeansEqualizer.shared,
            queue: .main
        ) { [weak self] _ in
            self?.applyEqualizerToCurrentItem()
        }
        backendBlockObserver = NotificationCenter.default.addObserver(
            forName: .beansBackendBlockStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopPlaybackIfBackendBlocked()
        }
    }

    deinit {
        interruptionResumeWorkItem?.cancel()
        audioRecoveryWorkItem?.cancel()
        audioSessionWatchdogTimer?.invalidate()
        if let equalizerSettingsObserver {
            NotificationCenter.default.removeObserver(equalizerSettingsObserver)
        }
        if let backendBlockObserver {
            NotificationCenter.default.removeObserver(backendBlockObserver)
        }
    }

    /// 在首帧之后恢复轻量播放偏好，避免安装后启动阶段触碰系统媒体服务。
    func restorePersistedPlayMode() {
        guard let raw = defaults.string(forKey: playModeKey),
              let saved = PlayMode(rawValue: raw) else { return }
        guard playMode != saved else { return }
        playMode = saved
        if !queue.isEmpty {
            buildPlayOrder()
        }
    }

    // MARK: - 播放控制

    func play(songs: [Song], startAt index: Int = 0) {
        guard !songs.isEmpty else { return }
        guard ensurePlaybackAllowed() else { return }
        queue = songs
        buildPlayOrder()
        jumpToOrderPosition(min(max(index, 0), songs.count - 1))
    }

    /// 追加后台继续加载的私人漫游歌曲，不打断当前歌曲或重置播放位置。
    func append(songs newSongs: [Song]) {
        guard !newSongs.isEmpty else { return }
        let existing = Set(queue.map(\.identityKey))
        let additions = newSongs.filter { !existing.contains($0.identityKey) }
        guard !additions.isEmpty else { return }
        queue.append(contentsOf: additions)
        buildPlayOrder()
        savePersistedPlaybackState()
    }

    func playSong(_ song: Song, in context: [Song]) {
        play(songs: context, startAt: context.firstIndex(of: song) ?? 0)
    }

    /// 插队播放：把歌曲放到当前歌曲之后，不打断当前播放
    func playNext(_ song: Song) {
        guard !queue.isEmpty else {
            play(songs: [song], startAt: 0)
            return
        }
        let insertAt = currentIndex + 1
        queue.insert(song, at: min(insertAt, queue.count))
        switch playMode {
        case .shuffle:
            playOrder = playOrder.map { $0 >= insertAt ? $0 + 1 : $0 }
            let nextOrderPosition = min(orderPosition + 1, playOrder.count)
            playOrder.insert(min(insertAt, queue.count - 1), at: nextOrderPosition)
        default:
            buildPlayOrder()
        }
        savePersistedPlaybackState()
        Task { @MainActor in
            ToastCenter.shared.show("已加入下一首播放")
        }
    }

    /// 可选地恢复上次退出时的歌曲并立即播放，只在每次应用启动时执行一次。
    func resumePersistedPlaybackIfEnabled() {
        guard !didAttemptAutoResume else { return }
        didAttemptAutoResume = true
        guard defaults.object(forKey: autoResumeLastPlaybackKey) as? Bool ?? false,
              currentSong != nil else { return }
        loadCurrent(resumeAt: progress)
    }

    func togglePlayPause() {
        guard ensurePlaybackAllowed() else { return }
        guard let player else {
            guard currentSong != nil else { return }
            loadCurrent(resumeAt: progress)
            return
        }
        if player.timeControlStatus == .playing {
            clearAudioRecoveryIntent()
            isPlaying = false
            player.pause()
            stopAudioSessionWatchdog()
        } else {
            clearAudioRecoveryIntent()
            player.playImmediately(atRate: Float(rate))
            isPlaying = true
            startAudioSessionWatchdogIfNeeded()
        }
        savePersistedPlaybackState()
        updateNowPlaying()
    }

    func next(manual: Bool = true) {
        guard ensurePlaybackAllowed() else { return }
        guard !queue.isEmpty else { return }
        // 单曲循环只影响自然播放结束；用户手动点击下一首时始终切换歌曲。
        advance()
        loadCurrent()
    }

    func previous() {
        guard ensurePlaybackAllowed() else { return }
        guard !queue.isEmpty else { return }
        // 直接切换到上一首（不再做“播放超过 3 秒先重头播放”的判断）
        if playMode == .shuffle {
            orderPosition = (orderPosition - 1 + playOrder.count) % playOrder.count
            currentIndex = playOrder[orderPosition]
        } else {
            currentIndex = (currentIndex - 1 + queue.count) % queue.count
        }
        loadCurrent()
    }

    func seek(to seconds: Double) {
        // 与播放器的歌词游标保持同一套逻辑：以用户指定的时间立即更新，
        // 不等待 AVPlayer 回调，也不使用回调中的旧 currentTime 覆盖目标位置。
        let clamped = max(0, min(seconds, max(duration, currentSong?.duration ?? seconds)))
        progress = clamped
        lyricProgress = clamped
        seekRevision &+= 1
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        updateNowPlaying()
        savePersistedPlaybackState()
    }

    /// 歌词点击专用的精确跳转。
    /// 保持 AVPlayer 的当前播放意图，避免连续点歌词时上一笔跳转留下暂停状态。
    func seekPrecisely(to seconds: Double) {
        let knownDuration = max(duration, currentSong?.duration ?? seconds)
        let target = knownDuration > 0
            ? max(0, min(seconds, knownDuration))
            : max(0, seconds)
        let shouldKeepPlaying = isPlaying || player?.timeControlStatus == .playing
        let seekSongKey = currentSong?.identityKey
        seekRevision &+= 1
        let revision = seekRevision
        progress = target
        lyricProgress = target
        player?.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard finished else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.currentSong?.identityKey == seekSongKey,
                      self.seekRevision == revision else { return }
                self.progress = target
                self.lyricProgress = target
                self.lastPublishedProgress = target
                if shouldKeepPlaying {
                    self.player?.playImmediately(atRate: Float(self.rate))
                    self.isPlaying = true
                }
                self.updateNowPlaying()
                self.savePersistedPlaybackState()
                self.seekRevision &+= 1
            }
        }
        updateNowPlaying()
    }

    func seekBy(_ delta: Double) {
        seek(to: progress + delta)
    }

    func togglePlayMode() {
        switch playMode {
        case .sequential: playMode = .repeatOne
        case .repeatOne: playMode = .shuffle
        case .shuffle: playMode = .sequential
        }
        buildPlayOrder()
    }

    func setRate(_ newRate: Double) {
        rate = newRate
        if isPlaying {
            player?.playImmediately(atRate: Float(newRate))
        }
        updateNowPlaying()
    }

    func playQueueIndex(_ index: Int) {
        guard ensurePlaybackAllowed() else { return }
        guard queue.indices.contains(index) else { return }
        jumpToOrderPosition(index)
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index), queue.count > 1 else { return }
        let removedID = queue[index].id
        queue.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            currentIndex = min(currentIndex, queue.count - 1)
            loadCurrent()
        }
        buildPlayOrder(avoiding: removedID)
        savePersistedPlaybackState()
    }

    func retryCurrent() {
        guard ensurePlaybackAllowed() else { return }
        loadFailed = false
        loadCurrent()
    }

    /// 删除单条播放历史（含持久化）
    func removeHistory(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard history.indices.contains(index) else { continue }
            history.remove(at: index)
        }
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }

    /// 清空播放历史（含持久化）
    func clearHistory() {
        history.removeAll()
        defaults.removeObject(forKey: historyKey)
    }

    /// 清空队列，仅保留当前歌曲
    func clearQueue() {
        guard !queue.isEmpty else { return }
        if let current = currentSong {
            queue = [current]
            currentIndex = 0
        } else {
            queue = []
            currentIndex = 0
        }
        buildPlayOrder()
        savePersistedPlaybackState()
    }

    // MARK: - 睡眠定时

    func startSleepTimer(minutes: Int) {
        stopSleepTimer()
        sleepTimerEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerRemaining = minutes * 60
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let end = self.sleepTimerEndsAt else { return }
            let remain = Int(end.timeIntervalSinceNow)
            self.sleepTimerRemaining = max(0, remain)
            if remain <= 0 {
                self.stopSleepTimer()
                self.pausePlayback()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    func stopSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEndsAt = nil
        sleepTimerRemaining = 0
    }

    var sleepTimerFormatted: String? {
        guard sleepTimerRemaining > 0 else { return nil }
        return String(format: "%d:%02d", sleepTimerRemaining / 60, sleepTimerRemaining % 60)
    }

    private func pausePlayback() {
        clearAudioRecoveryIntent()
        isPlaying = false
        player?.pause()
        stopAudioSessionWatchdog()
        updateNowPlaying()
    }

    // MARK: - 播放顺序

    private func buildPlayOrder(avoiding removedID: Int? = nil) {
        switch playMode {
        case .shuffle:
            var indices = Array(queue.indices).filter { $0 != removedID }
            indices.shuffle()
            playOrder = indices
            orderPosition = 0
        default:
            playOrder = Array(queue.indices)
            orderPosition = currentIndex
        }
    }

    private func advance() {
        switch playMode {
        case .shuffle:
            guard !playOrder.isEmpty else { return }
            orderPosition = (orderPosition + 1) % playOrder.count
            currentIndex = playOrder[orderPosition]
        default:
            currentIndex = (currentIndex + 1) % queue.count
            orderPosition = currentIndex
        }
    }

    private func jumpToOrderPosition(_ index: Int) {
        currentIndex = index
        if playMode == .shuffle {
            orderPosition = 0
            if let pos = playOrder.firstIndex(of: index) {
                orderPosition = pos
            }
        } else {
            orderPosition = index
        }
        loadCurrent()
    }

    // MARK: - 播放

    private func restartCurrent() {
        guard ensurePlaybackAllowed() else { return }
        seek(to: 0)
        player?.playImmediately(atRate: Float(rate))
        isPlaying = true
        updateNowPlaying()
    }

    private func loadCurrent(resumeAt: Double? = nil, forceKugouStandard: Bool = false) {
        guard ensurePlaybackAllowed() else { return }
        guard let song = currentSong else { return }
        audioRecoveryWorkItem?.cancel()
        audioRecoveryWorkItem = nil
        stopAudioSessionWatchdog()
        clearAudioRecoveryIntent()
        loadGeneration += 1
        let generation = loadGeneration
        thirdPartyRetryExcludedHostsBySong.removeValue(forKey: song.identityKey)
        attemptedThirdPartyQualitiesBySong.removeValue(forKey: song.identityKey)
        attemptedQQOfficialBRsBySong.removeValue(forKey: song.identityKey)
        activeThirdPartyQuality = nil
        activeQQOfficialBR = nil
        playbackRecoveryInFlightSongKey = nil
        finalizedFailureSongKey = nil
        failureAutoSkipWorkItem?.cancel()
        failureAutoSkipWorkItem = nil
        playbackStallWorkItem?.cancel()
        playbackStallWorkItem = nil
        thirdPartyPrefetchTask?.cancel()
        thirdPartyPrefetchTask = nil
        qqThirdPartyFallbackSongKey = nil
        let initialProgress = max(0, min(resumeAt ?? 0, max(song.duration, 0)))
        // 切歌时同时解除旧 item，避免旧音频在新播放器建立期间残留输出。
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        duration = song.duration
        progress = initialProgress
        lyricProgress = initialProgress
        isPlaying = false
        isBuffering = true
        loadFailed = false
        pushHistory(song)
        savePersistedPlaybackState()
        Task {
            var urlString: String?
            var resolvedThirdParty: UnblockService.Resolved?
            var qqOfficialBR: String?
            var attemptedQQOfficialBRs: [String] = []
            // 官方地址失败后，使用已启用的自定义音源兜底。
            let enableUnblock = externalSourcesEnabled
            let strictUnlock = shouldLockOfficialOnly(song)
            let quality = (forceKugouStandard && song.source == .kugou) ? .standard : BeansAudioQuality.current
            let thirdPartyQuality = ThirdPartyAudioQuality.current
            BeansLogger.shared.log("▶ 开始播放：\(song.name) - \(song.artists)｜平台=\(song.source.rawValue) id=\(song.id) 音质=\(quality.level) 第三方音质=\(thirdPartyQuality.rawValue) 自定义音源=\(enableUnblock ? "开" : "关") 官方受限=\(strictUnlock ? "是" : "否")", level: .info)
            for attempt in 0..<3 {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    if Task.isCancelled { return }
                    BeansLogger.shared.log("播放地址解析重试：\(song.name)｜第 \(attempt + 1) 次", level: .debug)
                }
                urlString = nil
                resolvedThirdParty = nil
                qqOfficialBR = nil
                attemptedQQOfficialBRs = []
                if song.source == .kugou {
                urlString = try? await KugouMusicAPI.shared.songURL(song: song, quality: quality)
                if urlString == nil {
                    resolvedThirdParty = await kugouFallback(
                        song: song,
                        thirdPartyQuality: thirdPartyQuality,
                        enableUnblock: enableUnblock
                    )
                }
            } else if song.source == .qq, let mid = song.qqMid {
                // QQ 官方地址失败后只走 QQ 第三方音源，不跨平台匹配同名歌曲。
                let officialResult = try? await QQMusicAPI.shared.songURLResult(
                    songmid: mid,
                    mediaMid: song.qqMediaMid,
                    quality: quality
                )
                urlString = officialResult?.url
                qqOfficialBR = officialResult?.br
                attemptedQQOfficialBRs = officialResult?.attemptedBRs ?? []
                if urlString == nil {
                    (urlString, resolvedThirdParty) = await qqFallback(
                        song: song,
                        quality: quality,
                        thirdPartyQuality: thirdPartyQuality,
                        enableUnblock: enableUnblock,
                        strict: strictUnlock
                    )
                }
                } else {
                (urlString, resolvedThirdParty) = await neteaseResolve(
                    song: song,
                    quality: quality,
                    thirdPartyQuality: thirdPartyQuality,
                    enableUnblock: enableUnblock,
                    strict: strictUnlock
                    )
                }
                if urlString != nil || resolvedThirdParty != nil { break }
            }
            if let resolved = resolvedThirdParty {
                let notice = self.thirdPartyVIPNotice(for: song, sourceTitle: resolved.sourceTitle)
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    self.setupPlayer(
                        url: resolved.url,
                        thirdPartyVIPNotice: notice,
                        resumeAt: initialProgress,
                        isThirdParty: true,
                        thirdPartyQuality: resolved.quality
                    )
                    self.prefetchNextThirdPartyIfNeeded(currentWasThirdParty: true)
                }
                return
            }
            guard let urlString, let url = URL(string: urlString) else {
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    self.isBuffering = false
                    self.loadFailed = true
                    let failureMessage = beansLocalized(
                        "播放失败：\(self.playbackFailureMessage(for: song, reason: "解析播放地址失败"))",
                        "Playback failed: \(self.playbackFailureMessage(for: song, reason: "解析播放地址失败", english: true))"
                    )
                    BeansLogger.shared.log("播放失败：\(song.name) - \(failureMessage)｜音质=\(quality.level)", level: .error)
                    self.finishUnrecoverablePlaybackFailure(
                        song: song,
                        reason: "解析播放地址失败",
                        message: failureMessage
                    )
                }
                return
            }
            await MainActor.run {
                guard generation == self.loadGeneration else { return }
                self.setupPlayer(
                    url: url,
                    resumeAt: initialProgress,
                    qqOfficialBR: qqOfficialBR,
                    attemptedQQOfficialBRs: attemptedQQOfficialBRs
                )
                self.prefetchNextThirdPartyIfNeeded(currentWasThirdParty: false, song: song)
            }
        }
    }

    /// 当前歌曲已经通过第三方音源播放，或当前歌曲属于会员歌曲时，提前解析下一首。
    /// 解析结果只进入 UnblockService 的短缓存，不会改动播放队列或播放器状态。
    private func prefetchNextThirdPartyIfNeeded(currentWasThirdParty: Bool, song: Song? = nil) {
        guard externalSourcesEnabled,
              playMode != .repeatOne,
              currentWasThirdParty || song?.isVIP == true,
              let nextSong = nextSongForPrefetch else { return }

        thirdPartyPrefetchTask?.cancel()
        let quality = ThirdPartyAudioQuality.current
        thirdPartyPrefetchTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.resolveThirdParty(song: nextSong, quality: quality, strict: false)
        }
    }

    private var nextSongForPrefetch: Song? {
        guard !queue.isEmpty else { return nil }
        let nextIndex: Int
        if playMode == .shuffle, !playOrder.isEmpty {
            nextIndex = playOrder[(orderPosition + 1) % playOrder.count]
        } else {
            nextIndex = (currentIndex + 1) % queue.count
        }
        guard queue.indices.contains(nextIndex), nextIndex != currentIndex else { return nil }
        return queue[nextIndex]
    }

    /// 网易云播放地址解析：按设置音质取 URL，VIP/灰色歌曲交给第三方解锁。
    private func neteaseResolve(
        song: Song,
        quality: BeansAudioQuality,
        thirdPartyQuality: ThirdPartyAudioQuality = .current,
        enableUnblock: Bool,
        strict: Bool = false
    ) async -> (String?, UnblockService.Resolved?) {
        var urlString: String?
        var resolved: UnblockService.Resolved?
        let infos = try? await NetEaseAPI.shared.songURLInfo(ids: [song.id], level: quality.level)
        var info = infos?[song.id]
        if (info?.url == nil || info?.freeTrial == true), quality != .standard {
            // 高音质拿不到时自动回落到标准音质
            let fallback = try? await NetEaseAPI.shared.songURLInfo(ids: [song.id], level: "standard")
            info = fallback?[song.id]
        }
        BeansLogger.shared.log("网易云解析：\(song.name) 音质=\(quality.level) 官方URL=\(info?.url == nil ? "无" : "有") 试听=\(info?.freeTrial == true ? "是" : "否")", level: .debug)
        // 试听片段 / 无 URL 一律不直接播放，交给第三方解锁，避免"只能试听"
        if let u = info?.url, info?.freeTrial != true {
            urlString = u
        }
        if urlString == nil, enableUnblock {
            resolved = await UnblockService.resolve(
                name: song.name,
                artists: song.artists,
                neteaseID: song.id,
                songSource: .netease,
                quality: thirdPartyQuality,
                strict: strict
            )
        }
        BeansLogger.shared.log("网易云结果：\(song.name) 官方=\(urlString != nil ? "是" : "否") 第三方=\(resolved != nil ? "命中" : "未用/未命中")", level: .debug)
        return (urlString, resolved)
    }

    /// QQ 歌曲兜底：官方失败后只走 QQ 第三方接口，不跨平台匹配同名歌曲。
    private func qqFallback(
        song: Song,
        quality _: BeansAudioQuality,
        thirdPartyQuality: ThirdPartyAudioQuality = .current,
        enableUnblock: Bool,
        strict: Bool = false,
        excludedHosts: Set<String> = []
    ) async -> (String?, UnblockService.Resolved?) {
        guard enableUnblock else {
            BeansLogger.shared.log("QQ兜底：\(song.name) 第三方=未启用", level: .debug)
            return (nil, nil)
        }
        let resolved = await UnblockService.resolve(
            name: song.name,
            artists: song.artists,
            // QQ 专属音源要求传数字 songId；mid 仅作为兼容接口的后备参数。
            neteaseID: song.id,
            songSource: .qq,
            qqMid: song.qqMid,
            qqMediaMid: song.qqMediaMid,
            quality: thirdPartyQuality,
            strict: strict,
            excludedHosts: excludedHosts
        )
        BeansLogger.shared.log("QQ兜底：\(song.name) QQ第三方=\(resolved != nil ? "命中" : "未命中")", level: .debug)
        return (nil, resolved)
    }

    /// 酷狗兜底：官方播放失败后使用内置音源作为备选。
    private func kugouFallback(
        song: Song,
        thirdPartyQuality: ThirdPartyAudioQuality = .current,
        enableUnblock: Bool
    ) async -> UnblockService.Resolved? {
        guard enableUnblock else { return nil }
        let kugouID = song.kugouHash ?? song.kugouAlbumAudioId ?? ""
        if kugouID.isEmpty {
            BeansLogger.shared.log("酷狗兜底跳过：缺少 album_audio_id/hash", level: .debug)
        } else {
            let resolved = await UnblockService.resolve(
                name: song.name,
                artists: song.artists,
                neteaseID: 0,
                songSource: .kugou,
                kugouID: kugouID,
                quality: thirdPartyQuality
            )
            if let resolved {
                BeansLogger.shared.log("酷狗兜底：\(song.name) 酷狗音源=命中", level: .debug)
                return resolved
            }
        }

        let strict = shouldLockOfficialOnly(song)
        if let matched = await matchNetEaseSong(
            name: song.name,
            artists: song.artists,
            durationMS: Int(song.duration * 1000),
            strict: strict
        ) {
            let resolved = await UnblockService.resolve(
                name: matched.name,
                artists: matched.artists,
                neteaseID: matched.id,
                songSource: .netease,
                quality: thirdPartyQuality,
                strict: strict
            )
            BeansLogger.shared.log("酷狗兜底转网易云音源：\(song.name) -> \(matched.name) 第三方=\(resolved != nil ? "命中" : "未命中")", level: .debug)
            return resolved
        }

        BeansLogger.shared.log("酷狗兜底：\(song.name) 第三方=未命中", level: .debug)
        return nil
    }

    /// 不再按歌手硬拦截跨平台兜底，避免 QQ 官方失败后把可播的网易云链路一并阻断。
    private func shouldLockOfficialOnly(_ song: Song) -> Bool {
        false
    }

    /// 在网易云按 歌名+歌手 匹配同名歌曲（QQ vkey 失败时的免费播放兜底）
    private func matchNetEaseSong(name: String, artists: String, durationMS: Int, strict: Bool = false) async -> Song? {
        let keyword = ([name, artists].filter { !$0.isEmpty }).joined(separator: " ")
        guard !keyword.isEmpty,
              let results = try? await NetEaseAPI.shared.search(keyword: keyword, limit: 8),
              !results.isEmpty else { return nil }
        let target = Double(durationMS) / 1000.0
        let artistTokens = artists.lowercased().split(whereSeparator: { $0 == " " || $0 == "/" || $0 == "&" }).map(String.init)
        // 优先：歌手匹配 + 时长接近（兼容 Jay Chou 别名）
        if let hit = results.first(where: { song in
            let durOK = abs(song.duration - target) < 12
            let songArtists = song.artists.lowercased()
            let artistOK = artistTokens.contains { !$0.isEmpty && songArtists.contains($0) }
                || (songArtists.contains("周杰伦") && artists.lowercased().contains("jay chou"))
            return durOK && artistOK
        }) { return hit }
        // 严格模式（周杰伦等版权歌手）：找不到原唱直接放弃，绝不返回翻唱
        if strict { return nil }
        // 其次：仅时长接近（必须足够接近才用，避免张冠李戴）
        if let hit = results.min(by: { abs($0.duration - target) < abs($1.duration - target) }),
           abs(hit.duration - target) < 20 {
            return hit
        }
        // 找不到可靠匹配：宁可播放失败，也不播放错误歌曲
        return nil
    }

    /// 仅在高音质地址已经交给 AVPlayer 但实际无法打开时回退标准音质。
    /// 这样正常账号仍优先使用高音质，兼容部分旧系统或账号返回的不可解码资源。
    @discardableResult
    private func retryKugouAtStandardIfNeeded(error: Error?) -> Bool {
        guard let song = currentSong,
              song.source == .kugou,
              BeansAudioQuality.current != .standard,
              kugouStandardFallbackSongKey != song.identityKey else { return false }
        kugouStandardFallbackSongKey = song.identityKey
        let resume = progress
        BeansLogger.shared.log("酷狗高音质地址无法打开，自动回退标准音质：歌曲=\(song.name) 系统=\(UIDevice.current.systemVersion) 错误=\(error?.localizedDescription ?? "未知错误")", level: .debug)
        loadCurrent(resumeAt: resume, forceKugouStandard: true)
        return true
    }

    @discardableResult
    private func retryThirdPartyIfNeeded(excludingHost: String? = nil) -> Bool {
        guard let song = currentSong,
              externalSourcesEnabled else { return false }
        if playbackRecoveryInFlightSongKey == song.identityKey {
            return true
        }

        let generation = loadGeneration
        let resume = progress
        let strict = shouldLockOfficialOnly(song)
        let currentQuality = activeThirdPartyQuality ?? ThirdPartyAudioQuality.current
        let attempted = attemptedThirdPartyQualitiesBySong[song.identityKey] ?? []
        guard let thirdPartyQuality = currentQuality.fallbackChain.first(where: {
            !attempted.contains($0.rawValue)
        }) else {
            BeansLogger.shared.log(
                "第三方播放地址重试停止：歌曲=\(song.name)｜已无更低可用音质｜当前=\(currentQuality.rawValue)",
                level: .debug
            )
            return false
        }
        attemptedThirdPartyQualitiesBySong[song.identityKey, default: []].insert(thirdPartyQuality.rawValue)
        var excludedHosts = thirdPartyRetryExcludedHostsBySong[song.identityKey] ?? []
        if let excludingHost, !excludingHost.isEmpty {
            excludedHosts.insert(excludingHost.lowercased())
        }
        guard excludedHosts.count <= 6 else {
            BeansLogger.shared.log(
                "第三方播放地址重试停止：歌曲=\(song.name)｜已排除域名=\(excludedHosts.sorted().joined(separator: ","))",
                level: .debug
            )
            return false
        }
        thirdPartyRetryExcludedHostsBySong[song.identityKey] = excludedHosts
        playbackRecoveryInFlightSongKey = song.identityKey
        BeansLogger.shared.log(
            "第三方播放地址失效，自动降级重试：歌曲=\(song.name)｜音质=\(thirdPartyQuality.rawValue)｜系统=\(UIDevice.current.systemVersion)｜排除域名=\(excludedHosts.sorted().joined(separator: ","))",
            level: .debug
        )
        let excludedHostsForRetry = excludedHosts
        Task {
            let resolved = await self.resolveThirdParty(
                song: song,
                quality: thirdPartyQuality,
                strict: strict,
                excludedHosts: excludedHostsForRetry
            )
            await MainActor.run {
                guard generation == self.loadGeneration,
                      self.currentSong?.identityKey == song.identityKey else {
                    if self.playbackRecoveryInFlightSongKey == song.identityKey {
                        self.playbackRecoveryInFlightSongKey = nil
                    }
                    return
                }
                self.playbackRecoveryInFlightSongKey = nil
                if let resolved {
                    let notice = self.thirdPartyVIPNotice(for: song, sourceTitle: resolved.sourceTitle)
                    self.setupPlayer(
                        url: resolved.url,
                        thirdPartyVIPNotice: notice,
                        resumeAt: resume,
                        isThirdParty: true,
                        thirdPartyQuality: resolved.quality
                    )
                    BeansLogger.shared.log(
                        "第三方播放地址重试成功：\(song.name)｜音质=\(resolved.quality.rawValue)｜域名=\(resolved.url.host ?? "?")",
                        level: .info
                    )
                } else {
                    BeansLogger.shared.log(
                        "第三方播放地址重试未命中：歌曲=\(song.name)｜已排除域名=\(excludedHostsForRetry.sorted().joined(separator: ","))",
                        level: .debug
                    )
                    if self.retryThirdPartyIfNeeded() { return }
                    self.finishUnrecoverablePlaybackFailure(song: song, reason: "第三方播放地址重试失败")
                }
            }
        }
        return true
    }

    @discardableResult
    private func retryQQOfficialIfNeeded() -> Bool {
        guard let song = currentSong,
              song.source == .qq,
              let qqMid = song.qqMid,
              !qqMid.isEmpty else { return false }
        if playbackRecoveryInFlightSongKey == song.identityKey {
            return true
        }

        let officialBRs = ["F000", "M800", "M500", "C400"]
        let attempted = attemptedQQOfficialBRsBySong[song.identityKey] ?? []
        guard let nextBR = officialBRs.first(where: { !attempted.contains($0) }) else {
            return false
        }
        attemptedQQOfficialBRsBySong[song.identityKey, default: []].insert(nextBR)
        playbackRecoveryInFlightSongKey = song.identityKey
        let generation = loadGeneration
        let resume = progress
        BeansLogger.shared.log(
            "QQ 官方地址实际不可播放，继续切换官方音质：歌曲=\(song.name)｜BR=\(nextBR)",
            level: .debug
        )
        Task {
            let urlString = try? await QQMusicAPI.shared.songURL(
                songmid: qqMid,
                mediaMid: song.qqMediaMid,
                br: nextBR
            )
            await MainActor.run {
                guard generation == self.loadGeneration,
                      self.currentSong?.identityKey == song.identityKey else {
                    if self.playbackRecoveryInFlightSongKey == song.identityKey {
                        self.playbackRecoveryInFlightSongKey = nil
                    }
                    return
                }
                self.playbackRecoveryInFlightSongKey = nil
                if let urlString, let url = URL(string: urlString) {
                    self.setupPlayer(
                        url: url,
                        resumeAt: resume,
                        qqOfficialBR: nextBR
                    )
                    return
                }
                if self.retryQQOfficialIfNeeded() { return }
                if self.fallbackQQToThirdPartyIfNeeded() { return }
                self.finishUnrecoverablePlaybackFailure(song: song, reason: "QQ 官方音质均不可播放")
            }
        }
        return true
    }

    @discardableResult
    private func fallbackQQToThirdPartyIfNeeded() -> Bool {
        guard let song = currentSong,
              song.source == .qq,
              let qqMid = song.qqMid,
              !qqMid.isEmpty,
              qqThirdPartyFallbackSongKey != song.identityKey,
              externalSourcesEnabled else { return false }
        if playbackRecoveryInFlightSongKey == song.identityKey {
            return true
        }

        qqThirdPartyFallbackSongKey = song.identityKey
        playbackRecoveryInFlightSongKey = song.identityKey
        let generation = loadGeneration
        let resume = progress
        let strict = shouldLockOfficialOnly(song)
        let thirdPartyQuality = ThirdPartyAudioQuality.current
        BeansLogger.shared.log(
            "QQ 官方地址实际不可播放，切换第三方解析：歌曲=\(song.name)｜系统=\(UIDevice.current.systemVersion)",
            level: .debug
        )
        Task {
            let (_, resolved) = await self.qqFallback(
                song: song,
                quality: BeansAudioQuality.current,
                thirdPartyQuality: thirdPartyQuality,
                enableUnblock: true,
                strict: strict
            )
            await MainActor.run {
                guard generation == self.loadGeneration,
                      self.currentSong?.identityKey == song.identityKey else {
                    if self.playbackRecoveryInFlightSongKey == song.identityKey {
                        self.playbackRecoveryInFlightSongKey = nil
                    }
                    return
                }
                self.playbackRecoveryInFlightSongKey = nil
                if let resolved {
                    let notice = self.thirdPartyVIPNotice(for: song, sourceTitle: resolved.sourceTitle)
                    self.setupPlayer(
                        url: resolved.url,
                        thirdPartyVIPNotice: notice,
                        resumeAt: resume,
                        isThirdParty: true,
                        thirdPartyQuality: resolved.quality
                    )
                    BeansLogger.shared.log(
                        "QQ 官方失败后第三方切换成功：\(song.name)｜域名=\(resolved.url.host ?? "?")",
                        level: .info
                    )
                } else {
                    BeansLogger.shared.log("QQ 官方失败后 QQ 第三方仍未命中：\(song.name)", level: .debug)
                    self.finishUnrecoverablePlaybackFailure(song: song, reason: "QQ 第三方解析失败")
                }
            }
        }
        return true
    }

    private func setupPlayer(
        url: URL,
        thirdPartyVIPNotice: ThirdPartyVIPNotice? = nil,
        resumeAt: Double = 0,
        isThirdParty: Bool = false,
        thirdPartyQuality: ThirdPartyAudioQuality? = nil,
        qqOfficialBR: String? = nil,
        attemptedQQOfficialBRs: [String] = []
    ) {
        guard ensurePlaybackAllowed(), let loadedSong = currentSong else { return }
        if isThirdParty {
            let quality = thirdPartyQuality ?? ThirdPartyAudioQuality.current
            activeThirdPartyQuality = quality
            activeQQOfficialBR = nil
            if let songKey = currentSong?.identityKey {
                attemptedThirdPartyQualitiesBySong[songKey, default: []].insert(quality.rawValue)
            }
        } else {
            activeThirdPartyQuality = nil
            activeQQOfficialBR = qqOfficialBR
            if let songKey = currentSong?.identityKey, !attemptedQQOfficialBRs.isEmpty {
                attemptedQQOfficialBRsBySong[songKey, default: []].formUnion(attemptedQQOfficialBRs)
            }
        }
        prepareForSystemPlayback()
        configureAudioSession()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        removeCurrentObservers()
        pendingThirdPartyVIPNotice = thirdPartyVIPNotice
        // QQ CDN 地址需要基础请求头；第三方地址也可能落在
        // ptqqmusic.gitv.tv / aqqmusic.tc.qq.com 等 QQ CDN 域名。
        // 这些地址在低系统上如果缺少 Referer/Cookie，常见表现是先进入
        // playing，随后以 AVFoundation -11849 失败。
        let item: AVPlayerItem
        var playbackHeaders: [String: String] = [:]
        if isQQAudioHost(url.host) {
            playbackHeaders = [
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:80.0) Gecko/20100101 Firefox/80.0",
                "Referer": "https://y.qq.com/",
            ]
            let cookie = QQMusicAuth.shared.cookieHeader
            if !cookie.isEmpty {
                playbackHeaders["Cookie"] = cookie
            }
            let asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": playbackHeaders
            ])
            item = AVPlayerItem(asset: asset)
        } else if url.host?.contains("kugou.com") == true || url.host?.contains("kgimg.com") == true {
            playbackHeaders = [
                "User-Agent": "Android15-1070-11440-46-0-DiscoveryDRADProtocol-wifi",
                "Referer": "https://www.kugou.com/",
            ]
            let cookie = KugouMusicAuth.shared.cookieHeader
            if !cookie.isEmpty { playbackHeaders["Cookie"] = cookie }
            let asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": playbackHeaders
            ])
            item = AVPlayerItem(asset: asset)
        } else {
            item = AVPlayerItem(url: url)
        }
        let headerKeys = playbackHeaders.keys.sorted().joined(separator: ",")
        BeansLogger.shared.log(
            "AVPlayer 准备播放：\(currentSong?.name ?? "?")｜URL=\(playbackURLSummary(url))｜第三方=\(isThirdParty ? "是" : "否")｜headers=\(playbackHeaders.isEmpty ? "未添加" : "已添加")｜headerKeys=\(headerKeys.isEmpty ? "无" : headerKeys)",
            level: .debug
        )
        let player = AVPlayer(playerItem: item)
        // QQ CDN 返回的首包较小，避免 AVPlayer 为了预缓冲过久而表现为
        // “点击后没反应”；真正不可播放时仍由 item 失败回调触发音质降级。
        player.automaticallyWaitsToMinimizeStalling = false
        player.rate = Float(rate)
        self.player = player
        logAudioOutputEnvironment(context: "创建播放器", item: item)
        configureEqualizer(for: item)
        playbackConfirmed = false
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            self.performOnMain { [weak self] in
                guard let self,
                      self.player === player,
                      self.currentSong?.identityKey == loadedSong.identityKey else { return }
                if item.status == .readyToPlay {
                    self.logAudioOutputEnvironment(context: "音频就绪", item: item)
                    return
                }
                guard item.status == .failed else { return }
                self.logPlaybackFailure(
                    reason: "AVPlayerItem.status.failed",
                    item: item,
                    url: url,
                    isThirdParty: isThirdParty,
                    playbackHeaders: playbackHeaders
                )
                if isThirdParty && self.retryThirdPartyIfNeeded(excludingHost: url.host) { return }
                if !isThirdParty && self.retryQQOfficialIfNeeded() { return }
                if !isThirdParty && self.fallbackQQToThirdPartyIfNeeded() { return }
                if self.retryKugouAtStandardIfNeeded(error: item.error) { return }
                self.finishUnrecoverablePlaybackFailure(song: loadedSong, reason: "AVPlayerItem 加载失败")
            }
        }
        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            self.performOnMain { [weak self] in
                guard let self, self.player === player else { return }
                if player.timeControlStatus == .paused, self.isPlaying {
                    if self.mixesWithOthers,
                       item.status == .readyToPlay {
                        // 某些外部音频只会让 AVPlayer 暂停，不会发出完整的 interruption
                        // 通知；保留播放意图，等系统音频会话释放后自动恢复。
                        self.rememberAudioPlaybackIntent()
                        self.isPlaying = false
                        self.refreshNowPlayingOwnership()
                        self.scheduleAudioRecovery(reason: "外部音频暂停播放器", delay: 0.25)
                    } else if self.audioLossInProgress {
                        self.isPlaying = false
                        self.refreshNowPlayingOwnership()
                    }
                }
                if player.timeControlStatus == .playing, self.audioLossInProgress {
                    self.isPlaying = true
                }
                if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    self.isBuffering = true
                    self.playbackStallWorkItem?.cancel()
                    let stall = DispatchWorkItem { [weak self, weak player, weak item] in
                        guard let self,
                              let player,
                              let item,
                              self.player === player,
                              player.currentItem === item,
                              self.currentSong?.identityKey == loadedSong.identityKey,
                              player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
                              !self.playbackConfirmed else { return }
                        BeansLogger.shared.log(
                            "播放地址长时间未开始：歌曲=\(self.currentSong?.name ?? "?")｜第三方=\(isThirdParty ? "是" : "否")｜URL=\(self.playbackURLSummary(url))",
                            level: .debug
                        )
                        if isThirdParty && self.retryThirdPartyIfNeeded(excludingHost: url.host) { return }
                        if !isThirdParty && self.retryQQOfficialIfNeeded() { return }
                        if !isThirdParty && self.fallbackQQToThirdPartyIfNeeded() { return }
                        if self.retryKugouAtStandardIfNeeded(error: item.error) { return }
                        self.finishUnrecoverablePlaybackFailure(
                            song: loadedSong,
                            reason: "播放地址长时间未响应"
                        )
                    }
                    self.playbackStallWorkItem = stall
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: stall)
                    return
                }
                self.playbackStallWorkItem?.cancel()
                self.playbackStallWorkItem = nil
                guard player.timeControlStatus == .playing, !self.playbackConfirmed else { return }
                self.playbackConfirmationWorkItem?.cancel()
                let confirmation = DispatchWorkItem { [weak self, weak player, weak item] in
                    guard let self,
                          let player,
                          let item,
                          self.player === player,
                          player.currentItem === item,
                          player.timeControlStatus == .playing,
                          item.status == .readyToPlay,
                          !self.playbackConfirmed else { return }
                    self.playbackConfirmed = true
                    if let song = self.currentSong {
                        BeansLogger.shared.log(
                            "▶ 播放成功确认：\(song.name)｜URL=\(self.playbackURLSummary(url))｜第三方=\(isThirdParty ? "是" : "否")｜itemStatus=\(self.playerItemStatusDescription(item.status))",
                            level: .info
                        )
                    }
                    self.showPendingThirdPartyVIPNoticeIfNeeded()
                }
                self.playbackConfirmationWorkItem = confirmation
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: confirmation)
            }
        }
        if resumeAt > 0.5 {
            let seekTime = CMTime(seconds: resumeAt, preferredTimescale: 600)
            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
            progress = resumeAt
        }
        player.playImmediately(atRate: Float(rate))
        isPlaying = true
        isBuffering = false
        loadFailed = false
        startAudioSessionWatchdogIfNeeded()
        // 修复：播放次数原先在 loadCurrent 里预计数，URL 加载失败/手动重试也会 +1，
        // 导致统计异常；改为真正开始播放时计数，且同一首歌同一会话只计一次。
        if let song = currentSong, lastCountedSongID != song.identityKey {
            bumpPlayCount(song)
            lastCountedSongID = song.identityKey
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self, let player = self.player else { return }
            if time.seconds.isFinite {
                self.lyricProgress = time.seconds
                if abs(time.seconds - self.lastPublishedProgress) >= 0.18 {
                    self.lastPublishedProgress = time.seconds
                    self.progress = time.seconds
                    if abs(time.seconds - self.lastPersistedProgress) >= 2.0 {
                        self.lastPersistedProgress = time.seconds
                        self.savePersistedPlaybackState()
                    }
                }
                // 其他音频 App 播放时可能会覆盖系统唯一的 Now Playing 信息。
                // 混音模式下定期重发轻量状态，让 Beans 继续保持锁屏/灵动岛控制权。
                let uptime = ProcessInfo.processInfo.systemUptime
                if self.isPlaying,
                   self.mixesWithOthers,
                   uptime - self.lastNowPlayingRefreshUptime >= 0.6 {
                    self.lastNowPlayingRefreshUptime = uptime
                    self.refreshNowPlayingOwnership()
                }
            }
            if let itemDuration = player.currentItem?.duration, itemDuration.isNumeric {
                let seconds = itemDuration.seconds
                if seconds.isFinite, abs(seconds - self.duration) > 0.25 {
                    self.duration = seconds
                }
            }
            let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            if waiting != self.isBuffering {
                self.isBuffering = waiting
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.playMode == .repeatOne {
                self.restartCurrent()
            } else {
                self.advance()
                self.loadCurrent()
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self,
                  self.player?.currentItem === item,
                  self.currentSong?.identityKey == loadedSong.identityKey else { return }
            self.logPlaybackFailure(
                reason: "AVPlayerItemFailedToPlayToEndTime",
                item: item,
                url: url,
                isThirdParty: isThirdParty,
                playbackHeaders: playbackHeaders
            )
            if !isThirdParty && self.retryQQOfficialIfNeeded() { return }
            if !isThirdParty && self.fallbackQQToThirdPartyIfNeeded() { return }
            if isThirdParty && self.retryThirdPartyIfNeeded(excludingHost: url.host) { return }
            if self.retryKugouAtStandardIfNeeded(error: item.error) { return }
            self.finishUnrecoverablePlaybackFailure(song: loadedSong, reason: "播放中断失败")
        }
        updateNowPlaying()
    }

    /// AVFoundation KVO callbacks are not guaranteed to arrive on the main
    /// thread. Serialize callbacks that touch ObservableObject state before
    /// reading or mutating the player model.
    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func finishUnrecoverablePlaybackFailure(
        song: Song?,
        reason: String,
        message: String? = nil
    ) {
        loadFailed = true
        isBuffering = false
        isPlaying = false
        stopAudioSessionWatchdog()
        guard let failedSong = song,
              currentSong?.identityKey == failedSong.identityKey,
              finalizedFailureSongKey != failedSong.identityKey else {
            return
        }
        finalizedFailureSongKey = failedSong.identityKey
        let shouldAutoSkip = defaults.object(forKey: autoSkipOnFailureKey) as? Bool ?? true
        let failureMessage: String
        if shouldAutoSkip && queue.count > 1 {
            failureMessage = beansLocalized(
                "播放失败：\(playbackFailureMessage(for: failedSong, reason: reason))，已自动切换到下一首",
                "Playback failed: \(playbackFailureMessage(for: failedSong, reason: reason, english: true)). Switched to the next song automatically."
            )
        } else {
            failureMessage = message ?? beansLocalized(
                "播放失败：\(playbackFailureMessage(for: failedSong, reason: reason))",
                "Playback failed: \(playbackFailureMessage(for: failedSong, reason: reason, english: true))"
            )
        }
        Task { @MainActor in
            ToastCenter.shared.show(failureMessage, duration: 3)
        }
        guard shouldAutoSkip, queue.count > 1 else { return }
        BeansLogger.shared.log("播放失败自动下一首：\(failedSong.name)｜原因=\(reason)", level: .info)
        let failedSongKey = failedSong.identityKey
        let failedGeneration = loadGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.loadGeneration == failedGeneration,
                  self.currentSong?.identityKey == failedSongKey,
                  self.finalizedFailureSongKey == failedSongKey else {
                return
            }
            self.failureAutoSkipWorkItem = nil
            self.next(manual: false)
        }
        failureAutoSkipWorkItem?.cancel()
        failureAutoSkipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func playbackFailureMessage(for song: Song, reason: String, english: Bool = false) -> String {
        let category = playbackFailureCategory(for: song, reason: reason)
        if english {
            switch category {
            case .membership:
                return "this song may require a platform membership; sign in to the platform and try again"
            case .network:
                return "the source timed out or the network is unavailable; check the connection and try again"
            case .sourceUnavailable:
                return "the platform did not return a playable address"
            case .unsupportedFormat:
                return "the returned audio format is not supported on this device"
            case .thirdPartyUnavailable:
                return "all enabled custom sources failed to return a playable address"
            case .unknown:
                return "the audio address could not be loaded; try again or switch songs"
            }
        }

        switch category {
        case .membership:
            return "该歌曲可能需要平台会员，请登录平台账号后重试"
        case .network:
            return "音源请求超时或网络不可用，请检查网络后重试"
        case .sourceUnavailable:
            return "平台没有返回可播放地址"
        case .unsupportedFormat:
            return "返回的音频格式不受当前设备支持"
        case .thirdPartyUnavailable:
            return "所有已启用的自定义音源都没有返回可播放地址"
        case .unknown:
            return "音频地址加载失败，请重试或切换歌曲"
        }
    }

    private func playbackFailureCategory(for song: Song, reason: String) -> PlaybackFailureCategory {
        let normalizedReason = reason.lowercased()
        if normalizedReason.contains("长时间") || normalizedReason.contains("timeout") || normalizedReason.contains("超时") {
            return .network
        }
        if normalizedReason.contains("第三方") || normalizedReason.contains("自定义") {
            return .thirdPartyUnavailable
        }
        if normalizedReason.contains("格式") || normalizedReason.contains("解码") || normalizedReason.contains("unsupported") {
            return .unsupportedFormat
        }
        if song.isVIP && !hasMembership(for: song.source) && !externalSourcesEnabled {
            return .membership
        }
        if normalizedReason.contains("解析") || normalizedReason.contains("地址") || normalizedReason.contains("加载") {
            return .sourceUnavailable
        }
        return .unknown
    }

    private func ensurePlaybackAllowed() -> Bool {
        guard !defaults.bool(forKey: BeansBackendSettings.blockedKey) else {
            stopPlaybackIfBackendBlocked(showToast: true)
            return false
        }
        return true
    }

    /// 统一按当前歌曲平台重新解析第三方地址，失败重试时不跨平台匹配同名歌曲。
    private func resolveThirdParty(
        song: Song,
        quality: ThirdPartyAudioQuality,
        strict: Bool,
        excludedHosts: Set<String> = []
    ) async -> UnblockService.Resolved? {
        switch song.source {
        case .netease:
            return await UnblockService.resolve(
                name: song.name,
                artists: song.artists,
                neteaseID: song.id,
                songSource: .netease,
                quality: quality,
                strict: strict,
                excludedHosts: excludedHosts
            )
        case .qq:
            return await qqFallback(
                song: song,
                quality: BeansAudioQuality.current,
                thirdPartyQuality: quality,
                enableUnblock: true,
                strict: strict,
                excludedHosts: excludedHosts
            ).1
        case .kugou:
            let kugouID = song.kugouHash ?? song.kugouAlbumAudioId
            guard let kugouID, !kugouID.isEmpty else { return nil }
            return await UnblockService.resolve(
                name: song.name,
                artists: song.artists,
                neteaseID: 0,
                songSource: .kugou,
                kugouID: kugouID,
                quality: quality,
                excludedHosts: excludedHosts
            )
        }
    }

    private func stopPlaybackIfBackendBlocked(showToast: Bool = false) {
        guard defaults.bool(forKey: BeansBackendSettings.blockedKey) else { return }
        clearAudioRecoveryIntent()
        loadGeneration += 1
        playbackConfirmationWorkItem?.cancel()
        failureAutoSkipWorkItem?.cancel()
        failureAutoSkipWorkItem = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        removeCurrentObservers()
        player = nil
        isPlaying = false
        isBuffering = false
        loadFailed = true
        updateNowPlaying()
        if showToast {
            Task { @MainActor in
                ToastCenter.shared.show("当前设备暂不可播放")
            }
        }
    }

    private func isQQAudioHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host.contains("qq.com")
            || host.contains("qqmusic")
            || host.contains("ptqqmusic")
    }

    private func playbackURLSummary(_ url: URL) -> String {
        let host = url.host ?? "?"
        let path = url.path.isEmpty ? "/" : url.path
        let shortPath = path.count > 72 ? String(path.prefix(72)) + "..." : path
        return "\(host)\(shortPath)"
    }

    private func logAudioOutputEnvironment(context: String, item: AVPlayerItem? = nil) {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map { output in
            "\(output.portType.rawValue):\(output.portName)"
        }.joined(separator: ",")
        var format = "未知"
        if let track = item?.asset.tracks(withMediaType: .audio).first,
           let rawDescription = track.formatDescriptions.first {
            if let description = rawDescription as? CMAudioFormatDescription {
                let streamPointer = CMAudioFormatDescriptionGetStreamBasicDescription(description)
                if let streamPointer {
                    let stream = streamPointer.pointee
                    let formatID = audioFormatIdentifier(stream.mFormatID)
                    format = "\(formatID) \(Int(stream.mSampleRate))Hz \(stream.mChannelsPerFrame)ch"
                } else {
                    BeansLogger.shared.log(
                        "音频输出诊断：无法读取音频格式描述 context=\(context)",
                        level: .debug
                    )
                }
            }
        }
        BeansLogger.shared.log(
            "音频输出诊断：\(context)｜route=\(outputs.isEmpty ? "无" : outputs)｜sample=\(format)｜category=\(session.category)｜mode=\(session.mode.rawValue)",
            level: .debug
        )
    }

    private func audioFormatIdentifier(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    private func playerItemStatusDescription(_ status: AVPlayerItem.Status) -> String {
        switch status {
        case .unknown: return "unknown"
        case .readyToPlay: return "readyToPlay"
        case .failed: return "failed"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    private func sanitizedLogURI(_ rawURI: String?) -> String {
        guard let rawURI, !rawURI.isEmpty else { return "?" }
        if var components = URLComponents(string: rawURI) {
            components.query = nil
            components.fragment = nil
            if let host = components.host {
                let path = components.path.isEmpty ? "/" : components.path
                let shortPath = path.count > 72 ? String(path.prefix(72)) + "..." : path
                return "\(host)\(shortPath)"
            }
            return components.string.map { String($0.prefix(96)) } ?? String(rawURI.prefix(96))
        }
        return String(rawURI.prefix(96))
    }

    private func logPlaybackFailure(
        reason: String,
        item: AVPlayerItem,
        url: URL,
        isThirdParty: Bool,
        playbackHeaders: [String: String]
    ) {
        let error = item.error
        let nsError = error as NSError?
        let errorDescription = error?.localizedDescription ?? "未知错误"
        let errorCode = nsError.map { "\($0.domain):\($0.code)" } ?? "?"
        let eventDetails = item.errorLog()?.events.map { event in
            [
                "domain=\(event.errorDomain)",
                "code=\(event.errorStatusCode)",
                "uri=\(sanitizedLogURI(event.uri))",
                "comment=\(event.errorComment ?? "?")"
            ].joined(separator: " ")
        }.joined(separator: " | ") ?? ""
        let headerKeys = playbackHeaders.keys.sorted().joined(separator: ",")
        BeansLogger.shared.log(
            "播放地址加载失败：原因=\(reason)"
                + "｜错误=\(errorDescription)"
                + "｜URL=\(playbackURLSummary(url))"
                + "｜第三方=\(isThirdParty ? "是" : "否")"
                + "｜headers=\(playbackHeaders.isEmpty ? "未添加" : "已添加")"
                + "｜headerKeys=\(headerKeys.isEmpty ? "无" : headerKeys)"
                + "｜itemStatus=\(playerItemStatusDescription(item.status))"
                + "｜NSError=\(errorCode)"
                + "｜AVErrorLog=\(eventDetails.isEmpty ? "无" : eventDetails)",
            level: .error
        )
    }

    private func removeCurrentObservers() {
        stopAudioSessionWatchdog()
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        failureObserver = nil
        itemStatusObserver = nil
        timeControlStatusObserver = nil
        playbackConfirmationWorkItem?.cancel()
        playbackConfirmationWorkItem = nil
        failureAutoSkipWorkItem?.cancel()
        failureAutoSkipWorkItem = nil
        playbackStallWorkItem?.cancel()
        playbackStallWorkItem = nil
        playbackConfirmed = false
        pendingThirdPartyVIPNotice = nil
        lastPublishedProgress = -1
    }

    /// 均衡器通过 AVAudioMix 的音频处理 tap 工作，不改动 URL、队列或播放器状态。
    /// 曲目切换和开关均复用这里的挂载流程，避免让网络请求跑到主线程。
    private func applyEqualizerToCurrentItem() {
        guard let item = player?.currentItem else { return }
        configureEqualizer(for: item)
    }

    private func configureEqualizer(for item: AVPlayerItem) {
        guard BeansEqualizer.shared.isEnabled else {
            item.audioMix = nil
            return
        }

        let asset = item.asset
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) { [weak self, weak item, weak asset] in
            guard let self, let item, let asset else { return }
            var error: NSError?
            guard asset.statusOfValue(forKey: "tracks", error: &error) == .loaded,
                  let track = asset.tracks(withMediaType: .audio).first,
                  let mix = BeansEqualizer.shared.makeAudioMix(for: track) else {
                return
            }
            self.performOnMain { [weak self, weak item] in
                guard let self,
                      let item,
                      self.player?.currentItem === item,
                      BeansEqualizer.shared.isEnabled else { return }
                item.audioMix = mix
            }
        }
    }

    private func thirdPartyVIPNotice(for song: Song, sourceTitle: String) -> ThirdPartyVIPNotice? {
        guard song.isVIP else { return nil }
        guard defaults.object(forKey: thirdPartyVIPNoticeKey) as? Bool ?? true else { return nil }
        guard !hasMembership(for: song.source) else { return nil }
        let sourceName = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = sourceName.isEmpty ? "第三方音源" : "第三方音源「\(sourceName)」"
        return ThirdPartyVIPNotice(
            songKey: song.identityKey,
            message: "当前账号未识别到对应会员，《\(song.name)》已通过\(suffix)播放"
        )
    }

    private func showPendingThirdPartyVIPNoticeIfNeeded() {
        guard let notice = pendingThirdPartyVIPNotice else { return }
        guard currentSong?.identityKey == notice.songKey else {
            pendingThirdPartyVIPNotice = nil
            return
        }
        guard defaults.object(forKey: thirdPartyVIPNoticeKey) as? Bool ?? true else {
            pendingThirdPartyVIPNotice = nil
            return
        }
        Task { @MainActor in
            ToastCenter.shared.show(notice.message)
        }
        BeansLogger.shared.log("第三方音源会员歌提醒：\(notice.message)", level: .info)
        pendingThirdPartyVIPNotice = nil
    }

    private func hasMembership(for source: SongSource) -> Bool {
        switch source {
        case .qq:
            return QQMusicAuth.shared.vipBadge != nil
        case .kugou:
            return KugouMusicAuth.shared.vipBadge != nil
        case .netease:
            guard let data = defaults.data(forKey: "beans.user"),
                  let user = try? JSONDecoder().decode(NetEaseUser.self, from: data) else {
                return false
            }
            return user.vipBadge != nil
        }
    }

    private func configureAudioSession() {
        if Self.applyAudioMixPreference(mixesWithOthers) {
            sessionConfigured = true
        } else {
            sessionConfigured = false
        }
    }

    @discardableResult
    static func applyAudioMixPreference(_ mixesWithOthers: Bool) -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            // 「与其他音频同时播放」开关：开启时 mixWithOthers，打开其他音频软件也能继续播放；关闭则自动暂停
            let options: AVAudioSession.CategoryOptions = mixesWithOthers ? [.mixWithOthers] : []
            let policy: AVAudioSession.RouteSharingPolicy = mixesWithOthers ? .default : .longFormAudio
            try session.setCategory(.playback, mode: .default, policy: policy, options: options)
            try session.setActive(true)
            if mixesWithOthers, !session.categoryOptions.contains(.mixWithOthers) {
                BeansLogger.shared.log("音频混合选项未生效", level: .warn)
                return false
            }
            return true
        } catch {
            BeansLogger.shared.log("音频会话配置失败：\(error.localizedDescription)", level: .error)
            return false
        }
    }

    /// 延后初始化系统音频服务，降低自签安装后首次启动时的兼容性风险。
    /// 播放真正开始前由 setupPlayer 兜底调用，因此不会影响播放器功能。
    private func prepareForSystemPlayback() {
        guard !systemPlaybackPrepared else { return }
        systemPlaybackPrepared = true
        observeInterruptions()
        observeRouteChanges()
        setupRemoteCommands()
    }

    private func observeRouteChanges() {
        guard !routeObserverInstalled else { return }
        routeObserverInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    /// 输出设备变化（插拔耳机 / 切换扬声器 / 来电路由等）后重新激活会话，避免播放无声
    @objc private func handleRouteChange(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleRouteChange(notification)
            }
            return
        }
        sessionConfigured = false
        if isPlaying || player?.timeControlStatus == .playing {
            rememberAudioPlaybackIntent()
        }
        if shouldResumeAfterAudioLoss || isPlaying || player?.timeControlStatus == .playing {
            scheduleAudioRecovery(reason: "音频路由变化", delay: 0.12)
        }
    }

    // MARK: - 来电/中断处理

    private func observeInterruptions() {
        guard !interruptionObserverInstalled else { return }
        interruptionObserverInstalled = true
        let session = AVAudioSession.sharedInstance()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
        guard !secondaryAudioHintObserverInstalled else { return }
        secondaryAudioHintObserverInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSecondaryAudioHint(_:)),
            name: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: session
        )
        guard !mediaServicesObserverInstalled else { return }
        mediaServicesObserverInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
        guard !applicationAudioObserverInstalled else { return }
        applicationAudioObserverInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationWillResignActive(_:)),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidBecomeActive(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleInterruption(notification)
            }
            return
        }
        guard let info = notification.userInfo,
              let rawValue = info[AVAudioSessionInterruptionTypeKey] else { return }
        let rawType: UInt
        if let number = rawValue as? NSNumber {
            rawType = number.uintValue
        } else if let value = rawValue as? UInt {
            rawType = value
        } else {
            return
        }
        guard let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            interruptionResumeWorkItem?.cancel()
            interruptionResumeWorkItem = nil
            interruptionInProgress = true
            rememberAudioPlaybackIntent()
            // 混音模式下系统可能只暂停 AVPlayer 而不改变我们的状态；恢复统一交给
            // 结束通知和次级音频提示，避免在系统仍占用音频会话时抢先播放。
            if !mixesWithOthers {
                isPlaying = false
                player?.pause()
                updateNowPlaying()
            } else {
                sessionConfigured = false
                scheduleAudioRecovery(reason: "mixed audio interruption", delay: 0.2)
                refreshNowPlayingOwnership()
            }
        case .ended:
            sessionConfigured = false
            guard interruptionInProgress || shouldResumeAfterAudioLoss else { return }
            scheduleAudioRecovery(reason: "系统音频中断结束", delay: 0.18)
        @unknown default:
            break
        }
    }

    /// 开启混音后，视频/语音类音频通常只发送这个通知，不发送完整 interruption ended 回调。
    @objc private func handleSecondaryAudioHint(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleSecondaryAudioHint(notification)
            }
            return
        }
        guard mixesWithOthers else { return }
        let rawValue = notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey]
        let rawType: UInt?
        if let number = rawValue as? NSNumber {
            rawType = number.uintValue
        } else {
            rawType = rawValue as? UInt
        }
        // 系统定义 began=1、ended=0；使用原始值兼容旧系统 SDK。
        if rawType == 1 {
            rememberAudioPlaybackIntent()
            sessionConfigured = false
            scheduleAudioRecovery(reason: "次级音频开始", delay: 0.12)
            refreshNowPlayingOwnership()
        } else {
            sessionConfigured = false
            scheduleAudioRecovery(reason: "次级音频结束", delay: 0.12)
        }
    }

    @objc private func handleMediaServicesReset(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleMediaServicesReset(notification)
            }
            return
        }
        sessionConfigured = false
        guard currentSong != nil else { return }
        rememberAudioPlaybackIntent()
        scheduleAudioRecovery(reason: "系统音频服务重置", delay: 0.2)
    }

    @objc private func handleApplicationWillResignActive(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleApplicationWillResignActive(notification)
            }
            return
        }
        guard isPlaying || player?.timeControlStatus == .playing else { return }
        rememberAudioPlaybackIntent()
    }

    @objc private func handleApplicationDidBecomeActive(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleApplicationDidBecomeActive(notification)
            }
            return
        }
        guard currentSong != nil else { return }
        sessionConfigured = false
        if shouldResumeAfterAudioLoss || isPlaying || player?.timeControlStatus == .playing {
            scheduleAudioRecovery(reason: "应用重新激活", delay: 0.12)
        }
    }

    private func rememberAudioPlaybackIntent() {
        guard currentSong != nil else { return }
        let active = isPlaying || player?.timeControlStatus == .playing || player?.rate != 0
        if active {
            shouldResumeAfterAudioLoss = true
            wasPlayingBeforeInterruption = true
        }
        audioLossInProgress = true
    }

    private func clearAudioRecoveryIntent() {
        shouldResumeAfterAudioLoss = false
        audioLossInProgress = false
        interruptionInProgress = false
        wasPlayingBeforeInterruption = false
        audioRecoveryWorkItem?.cancel()
        audioRecoveryWorkItem = nil
        interruptionResumeWorkItem?.cancel()
        interruptionResumeWorkItem = nil
    }

    /// 混音播放时，部分应用既不发送完整中断通知，也会暂停 AVPlayer 的时间回调。
    /// 用主线程定时器补足这条通知链，同时重新发布系统正在播放信息。
    private func startAudioSessionWatchdogIfNeeded() {
        guard mixesWithOthers,
              currentSong != nil,
              audioSessionWatchdogTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.performOnMain { [weak self] in
                self?.handleAudioSessionWatchdogTick()
            }
        }
        audioSessionWatchdogTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAudioSessionWatchdog() {
        audioSessionWatchdogTimer?.invalidate()
        audioSessionWatchdogTimer = nil
    }

    private func handleAudioSessionWatchdogTick() {
        guard mixesWithOthers, currentSong != nil else {
            stopAudioSessionWatchdog()
            return
        }
        guard let currentPlayer = player else {
            stopAudioSessionWatchdog()
            return
        }

        let itemReady = currentPlayer.currentItem?.status == .readyToPlay
        let playerIsPlaying = currentPlayer.timeControlStatus == .playing
        let playerIsPaused = currentPlayer.timeControlStatus == .paused

        if playerIsPaused, itemReady, (!interruptionInProgress || mixesWithOthers) {
            if !shouldResumeAfterAudioLoss {
                rememberAudioPlaybackIntent()
            }
            if isPlaying {
                isPlaying = false
                refreshNowPlayingOwnership()
            }
        }

        let session = AVAudioSession.sharedInstance()
        if !session.categoryOptions.contains(.mixWithOthers) {
            sessionConfigured = Self.applyAudioMixPreference(true)
        }
        let otherAudioIsActive = session.isOtherAudioPlaying || session.secondaryAudioShouldBeSilencedHint
        if shouldResumeAfterAudioLoss,
           !playerIsPlaying,
           itemReady,
           (mixesWithOthers || !otherAudioIsActive) {
            scheduleAudioRecovery(reason: "外部音频结束", delay: 0)
        }

        // 其它应用可能已经覆盖系统唯一的 Now Playing 槽位；播放期间持续重发，
        // 结束后也能立即恢复封面、控制中心和灵动岛内容。
        if playerIsPlaying || (shouldResumeAfterAudioLoss && !otherAudioIsActive) {
            let uptime = ProcessInfo.processInfo.systemUptime
            if uptime - lastNowPlayingRefreshUptime >= 0.6 {
                lastNowPlayingRefreshUptime = uptime
                refreshNowPlayingOwnership()
            }
        }
    }

    private func scheduleAudioRecovery(reason: String, delay: TimeInterval, attempt: Int = 0) {
        guard currentSong != nil else { return }
        guard shouldResumeAfterAudioLoss || isPlaying || player?.timeControlStatus == .playing else { return }
        audioRecoveryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.recoverAudioSession(reason: reason, attempt: attempt)
        }
        audioRecoveryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func recoverAudioSession(reason: String, attempt: Int) {
        guard currentSong != nil else { return }
        let session = AVAudioSession.sharedInstance()
        if !mixesWithOthers,
           session.isOtherAudioPlaying || session.secondaryAudioShouldBeSilencedHint {
            scheduleAudioRecovery(
                reason: reason,
                delay: min(0.8, 0.18 + Double(attempt) * 0.08),
                attempt: attempt + 1
            )
            return
        }

        sessionConfigured = false
        guard Self.applyAudioMixPreference(mixesWithOthers) else {
            scheduleAudioRecovery(reason: reason, delay: 0.35, attempt: attempt + 1)
            return
        }

        guard let currentPlayer = player else {
            let resume = progress
            clearAudioRecoveryIntent()
            loadCurrent(resumeAt: resume)
            return
        }
        if currentPlayer.currentItem == nil || currentPlayer.currentItem?.status == .failed {
            let resume = progress
            clearAudioRecoveryIntent()
            loadCurrent(resumeAt: resume)
            return
        }

        currentPlayer.playImmediately(atRate: Float(rate))
        isPlaying = true
        isBuffering = false
        audioLossInProgress = false
        shouldResumeAfterAudioLoss = false
        interruptionInProgress = false
        wasPlayingBeforeInterruption = false
        BeansLogger.shared.log("音频会话恢复：\(reason)｜歌曲=\(currentSong?.name ?? "?")", level: .debug)
        startAudioSessionWatchdogIfNeeded()
        refreshNowPlayingOwnership()
    }

    // MARK: - 播放历史与统计

    private func pushHistory(_ song: Song) {
        history.removeAll { $0.identityKey == song.identityKey }
        history.insert(song, at: 0)
        if history.count > 50 {
            history = Array(history.prefix(50))
        }
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard let data = defaults.data(forKey: historyKey),
              let saved = try? JSONDecoder().decode([Song].self, from: data) else { return }
        history = saved
    }

    private func bumpPlayCount(_ song: Song) {
        playCounts[song.identityKey, default: 0] += 1
        if let data = try? JSONEncoder().encode(playCounts) {
            defaults.set(data, forKey: countsKey)
        }
    }

    private func loadPlayCounts() {
        guard let data = defaults.data(forKey: countsKey),
              let saved = try? JSONDecoder().decode([String: Int].self, from: data) else { return }
        playCounts = saved
    }

    private func savePersistedPlaybackState() {
        guard !queue.isEmpty, queue.indices.contains(currentIndex) else {
            defaults.removeObject(forKey: playbackStateKey)
            return
        }
        let state = PersistedPlaybackState(
            queue: queue,
            currentIndex: currentIndex,
            progress: progress,
            duration: duration,
            savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: playbackStateKey)
        }
    }

    private func restorePersistedPlaybackState() {
        guard let data = defaults.data(forKey: playbackStateKey),
              let saved = try? JSONDecoder().decode(PersistedPlaybackState.self, from: data),
              !saved.queue.isEmpty else { return }
        queue = saved.queue
        currentIndex = min(max(saved.currentIndex, 0), saved.queue.count - 1)
        duration = max(saved.duration, currentSong?.duration ?? 0)
        progress = max(0, min(saved.progress, max(duration, currentSong?.duration ?? 0)))
        isPlaying = false
        isBuffering = false
        loadFailed = false
        buildPlayOrder()
    }

    /// 听歌排行：按播放次数排序的前几首
    var topPlayed: [(song: Song, count: Int)] {
        var result: [(song: Song, count: Int)] = []
        for (key, count) in playCounts {
            if let song = history.first(where: { $0.identityKey == key }) {
                result.append((song, count))
            }
        }
        return result.sorted { $0.count > $1.count }.prefix(8).map { $0 }
    }

    // MARK: - 系统正在播放

    private func updateNowPlaying() {
        guard nowPlayingEnabled else {
            clearNowPlayingInfo()
            return
        }
        guard let song = currentSong else { return }
        let sameSong = nowPlayingSongKey == song.identityKey
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyArtist: song.artists,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: max(duration, song.duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if sameSong, let artwork = nowPlayingInfo[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        if let artworkURL = song.coverURL {
            let artworkKey = song.identityKey + "|" + artworkURL.absoluteString
            if let cached = Self.nowPlayingArtworkCache.object(forKey: artworkURL as NSURL) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cached.size) { _ in cached }
            } else if lastNowPlayingArtworkKey != artworkKey {
                lastNowPlayingArtworkKey = artworkKey
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    if let data = try? Data(contentsOf: artworkURL), let image = UIImage(data: data) {
                        Self.nowPlayingArtworkCache.setObject(image, forKey: artworkURL as NSURL)
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        DispatchQueue.main.async {
                            guard let self,
                                  self.nowPlayingEnabled,
                                  self.currentSong?.identityKey == song.identityKey else { return }
                            self.nowPlayingSongKey = song.identityKey
                            self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                            self.publishNowPlayingInfo()
                        }
                    }
                }
            }
        } else {
            lastNowPlayingArtworkKey = nil
        }
        nowPlayingSongKey = song.identityKey
        nowPlayingInfo = info
        publishNowPlayingInfo()
    }

    /// 混音播放时只更新锁屏所需的轻量字段，避免重复下载或解码封面。
    /// 系统的 Now Playing 信息是全局单例，其他音乐 App 播放后需要重新声明当前内容。
    private func refreshNowPlayingOwnership() {
        guard nowPlayingEnabled, let song = currentSong else { return }
        guard nowPlayingSongKey == song.identityKey, !nowPlayingInfo.isEmpty else {
            updateNowPlaying()
            return
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? rate : 0.0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = max(duration, song.duration)
        if let artworkURL = song.coverURL,
           let cached = Self.nowPlayingArtworkCache.object(forKey: artworkURL as NSURL) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cached.size) { _ in cached }
        }
        publishNowPlayingInfo()
    }

    private func publishNowPlayingInfo() {
        guard nowPlayingEnabled, !nowPlayingInfo.isEmpty else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private func clearNowPlayingInfo() {
        lastNowPlayingArtworkKey = nil
        nowPlayingSongKey = nil
        nowPlayingInfo = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func setupRemoteCommands() {
        guard !remoteCommandsInstalled else { return }
        remoteCommandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.performOnMain { [weak self] in
                guard let self else { return }
                guard self.ensurePlaybackAllowed() else { return }
                self.clearAudioRecoveryIntent()
                self.player?.playImmediately(atRate: Float(self.rate))
                self.isPlaying = true
                self.updateNowPlaying()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.performOnMain { [weak self] in
                guard let self else { return }
                self.clearAudioRecoveryIntent()
                self.isPlaying = false
                self.player?.pause()
                self.stopAudioSessionWatchdog()
                self.updateNowPlaying()
            }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.performOnMain { [weak self] in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.performOnMain { [weak self] in self?.previous() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.performOnMain { [weak self] in self?.togglePlayPause() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.performOnMain { [weak self] in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    // MARK: - 与其他音频同时播放

    /// 与其他 App 音频混合播放。此开关与锁屏/灵动岛显示相互独立。
    var mixesWithOthers: Bool {
        get { defaults.object(forKey: audioMixKey) as? Bool ?? false }
        set { setMixesWithOthers(newValue) }
    }

    /// 更新混音会话后立即重申系统正在播放信息，避免混音开关影响锁屏和灵动岛显示。
    func setMixesWithOthers(_ enabled: Bool) {
        defaults.set(enabled, forKey: audioMixKey)
        sessionConfigured = false
        configureAudioSession()
        if enabled, isPlaying || player?.timeControlStatus == .playing {
            startAudioSessionWatchdogIfNeeded()
        } else if !enabled {
            stopAudioSessionWatchdog()
        }
        updateNowPlaying()
    }

    /// 独立控制锁屏和灵动岛的系统正在播放信息，不影响与其他音频混合播放。
    var nowPlayingEnabled: Bool {
        get { defaults.object(forKey: nowPlayingEnabledKey) as? Bool ?? true }
        set { setNowPlayingEnabled(newValue) }
    }

    func setNowPlayingEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: nowPlayingEnabledKey)
        if enabled {
            updateNowPlaying()
        } else {
            clearNowPlayingInfo()
        }
    }

}
