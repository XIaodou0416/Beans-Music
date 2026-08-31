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

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var playbackConfirmed = false
    private var pendingThirdPartyVIPNotice: ThirdPartyVIPNotice?
    private var sessionConfigured = false
    private var systemPlaybackPrepared = false
    private var routeObserverInstalled = false
    private var interruptionObserverInstalled = false
    private var remoteCommandsInstalled = false
    private var playOrder: [Int] = []
    private var orderPosition = 0
    private var sleepTimer: Timer?
    private var lastCountedSongID: String?
    private var wasPlayingBeforeInterruption = false
    private var lastPublishedProgress: Double = -1
    private var lastPersistedProgress: Double = -1
    private var lastNowPlayingArtworkKey: String?
    /// 酷狗高音质地址在部分账号/系统上会返回但无法由 AVPlayer 打开；每首歌只自动降级一次。
    private var kugouStandardFallbackSongKey: String?
    /// 第三方地址偶发过期或节点不可用时，按失败域名重试，避免同一节点反复进入播放器。
    private var thirdPartyRetryExcludedHostsBySong: [String: Set<String>] = [:]
    /// QQ 官方地址返回成功但实际不可播放时，只切换到第三方一次，避免官方/第三方之间循环。
    private var qqThirdPartyFallbackSongKey: String?
    private var playbackConfirmationWorkItem: DispatchWorkItem?
    private static let nowPlayingArtworkCache = NSCache<NSURL, UIImage>()

    private let historyKey = "beans.history"
    private let countsKey = "beans.playcounts"
    private let playbackStateKey = "beans.player.playbackState.v1"
    private let audioMixKey = "beans.audio.mixothers.v1"
    private let playModeKey = "beans.player.playMode"
    private let thirdPartyVIPNoticeKey = "beans.showThirdPartyVIPNotice"
    private let defaults = UserDefaults.standard

    private struct ThirdPartyVIPNotice {
        let songKey: String
        let message: String
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
        queue = songs
        buildPlayOrder()
        jumpToOrderPosition(min(max(index, 0), songs.count - 1))
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
        buildPlayOrder()
        savePersistedPlaybackState()
    }

    func togglePlayPause() {
        guard let player else {
            guard currentSong != nil else { return }
            loadCurrent(resumeAt: progress)
            return
        }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.playImmediately(atRate: Float(rate))
            isPlaying = true
        }
        savePersistedPlaybackState()
        updateNowPlaying()
    }

    func next(manual: Bool = true) {
        guard !queue.isEmpty else { return }
        if playMode == .repeatOne && manual {
            restartCurrent()
            return
        }
        advance()
        loadCurrent()
    }

    func previous() {
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
        let clamped = max(0, min(seconds, max(duration, 0)))
        progress = clamped
        // 用 seek 完成回调同步真实进度：避免暂停状态下拖动进度后，歌词定位与实际播放位置不一致
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard let self, finished else { return }
            let actual = self.player?.currentTime().seconds ?? clamped
            if abs(actual - self.progress) > 0.25 {
                self.progress = actual
            }
        }
        updateNowPlaying()
        savePersistedPlaybackState()
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
        player?.pause()
        isPlaying = false
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
        seek(to: 0)
        player?.playImmediately(atRate: Float(rate))
        isPlaying = true
        updateNowPlaying()
    }

    private func loadCurrent(resumeAt: Double? = nil, forceKugouStandard: Bool = false) {
        guard let song = currentSong else { return }
        loadGeneration += 1
        let generation = loadGeneration
        thirdPartyRetryExcludedHostsBySong.removeValue(forKey: song.identityKey)
        qqThirdPartyFallbackSongKey = nil
        let initialProgress = max(0, min(resumeAt ?? 0, max(song.duration, 0)))
        // 切歌立即暂停旧音频，避免新歌加载期间旧歌继续播放造成“切歌卡住”感
        player?.pause()
        duration = song.duration
        progress = initialProgress
        isPlaying = false
        isBuffering = true
        loadFailed = false
        pushHistory(song)
        savePersistedPlaybackState()
        Task {
            var urlString: String?
            var resolvedThirdParty: UnblockService.Resolved?
            // 免费听歌（灰色歌曲解锁）总开关：默认开启，官方失败后走同名歌曲与第三方音源兜底。
            let enableUnblock = defaults.object(forKey: "beans.enableUnblock") as? Bool ?? true
            let strictUnlock = shouldLockOfficialOnly(song)
            let quality = (forceKugouStandard && song.source == .kugou) ? .standard : BeansAudioQuality.current
            BeansLogger.shared.log("▶ 开始播放：\(song.name) - \(song.artists)｜平台=\(song.source.rawValue) id=\(song.id) 音质=\(quality.level) 免费听歌=\(enableUnblock ? "开" : "关") 官方受限=\(strictUnlock ? "是" : "否")", level: .info)
            if song.source == .kugou {
                urlString = try? await KugouMusicAPI.shared.songURL(song: song, quality: quality)
                if urlString == nil {
                    resolvedThirdParty = await kugouFallback(song: song, enableUnblock: enableUnblock)
                }
            } else if song.source == .qq, let mid = song.qqMid {
                // 官方优先；官方无地址后走完整兜底：QQ 音源、网易云同名匹配、网易云音源。
                urlString = try? await QQMusicAPI.shared.songURL(songmid: mid, mediaMid: song.qqMediaMid)
                if urlString == nil {
                    (urlString, resolvedThirdParty) = await qqFallback(song: song, quality: quality, enableUnblock: enableUnblock, strict: strictUnlock)
                }
            } else {
                (urlString, resolvedThirdParty) = await neteaseResolve(song: song, quality: quality, enableUnblock: enableUnblock, strict: strictUnlock)
            }
            if let resolved = resolvedThirdParty {
                let notice = self.thirdPartyVIPNotice(for: song, sourceTitle: resolved.sourceTitle)
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    self.setupPlayer(
                        url: resolved.url,
                        thirdPartyVIPNotice: notice,
                        resumeAt: initialProgress,
                        isThirdParty: true
                    )
                }
                return
            }
            guard let urlString, let url = URL(string: urlString) else {
                await MainActor.run {
                    guard generation == self.loadGeneration else { return }
                    self.isBuffering = false
                    self.loadFailed = true
                    let hasUserSourceKey = (UserDefaults.standard
                        .string(forKey: UnblockSourceStore.userAPIKeysKey)?
                        .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .isEmpty ?? true) == false
                    let failureMessage = enableUnblock
                        ? (hasUserSourceKey
                           ? "播放失败，可能是音源调用上限或地址失效，请稍后重试"
                           : "播放失败，您已开启第三方音源功能，请填写密钥后播放")
                        : "播放失败，未获取到可用音源"
                    BeansLogger.shared.log("播放失败：\(song.name) - \(failureMessage)｜音质=\(quality.level)", level: .error)
                    ToastCenter.shared.show(failureMessage, duration: 3)
                }
                return
            }
            await MainActor.run {
                guard generation == self.loadGeneration else { return }
                self.setupPlayer(url: url, resumeAt: initialProgress)
            }
        }
    }

    /// 网易云播放地址解析：按设置音质取 URL，VIP/灰色歌曲交给第三方解锁。
    private func neteaseResolve(song: Song, quality: BeansAudioQuality, enableUnblock: Bool, strict: Bool = false) async -> (String?, UnblockService.Resolved?) {
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
                strict: strict
            )
        }
        BeansLogger.shared.log("网易云结果：\(song.name) 官方=\(urlString != nil ? "是" : "否") 第三方=\(resolved != nil ? "命中" : "未用/未命中")", level: .debug)
        return (urlString, resolved)
    }

    /// QQ 歌曲兜底：优先复用网易云可播链路；仍不可播时再尝试 QQ 第三方源。
    private func qqFallback(song: Song, quality: BeansAudioQuality, enableUnblock: Bool, strict: Bool = false, excludedHosts: Set<String> = []) async -> (String?, UnblockService.Resolved?) {
        var urlString: String?
        var resolved: UnblockService.Resolved?
        if let matched = await matchNetEaseSong(name: song.name, artists: song.artists, durationMS: Int(song.duration * 1000), strict: strict) {
            let infos = try? await NetEaseAPI.shared.songURLInfo(ids: [matched.id], level: quality.level)
            var info = infos?[matched.id]
            if (info?.url == nil || info?.freeTrial == true), quality != .standard {
                let fallback = try? await NetEaseAPI.shared.songURLInfo(ids: [matched.id], level: "standard")
                info = fallback?[matched.id]
            }
            // 免费完整 URL 直接用；试听片段 / 无 URL 交给第三方解锁
            if let u = info?.url, info?.freeTrial != true {
                urlString = u
            } else if enableUnblock {
                resolved = await UnblockService.resolve(
                    name: matched.name,
                    artists: matched.artists,
                    neteaseID: matched.id,
                    songSource: .netease,
                    strict: strict
                )
            }
        }
        if resolved != nil || urlString != nil {
            BeansLogger.shared.log("QQ兜底：\(song.name) 网易云链路=命中 官方=\(urlString != nil ? "是" : "否") 第三方=\(resolved != nil ? "命中" : "未命中")", level: .debug)
            return (urlString, resolved)
        }
        if enableUnblock {
            resolved = await UnblockService.resolve(
                name: song.name,
                artists: song.artists,
                neteaseID: 0,
                songSource: .qq,
                qqMid: song.qqMid,
                qqMediaMid: song.qqMediaMid,
                strict: strict,
                excludedHosts: excludedHosts
            )
        }
        BeansLogger.shared.log("QQ兜底：\(song.name) 官方=\(urlString != nil ? "是" : "否") 第三方=\(resolved != nil ? "命中" : "未用/未命中")", level: .debug)
        return (urlString, resolved)
    }

    /// 酷狗兜底：官方播放失败后使用内置音源作为备选。
    private func kugouFallback(song: Song, enableUnblock: Bool) async -> UnblockService.Resolved? {
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
                kugouID: kugouID
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
              song.source == .qq,
              let qqMid = song.qqMid,
              !qqMid.isEmpty else { return false }

        let generation = loadGeneration
        let resume = progress
        let strict = shouldLockOfficialOnly(song)
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
        BeansLogger.shared.log(
            "第三方播放地址失效，重新解析一次：歌曲=\(song.name)｜系统=\(UIDevice.current.systemVersion)｜排除域名=\(excludedHosts.sorted().joined(separator: ","))",
            level: .debug
        )
        Task {
            let (urlString, resolved) = await self.qqFallback(
                song: song,
                quality: BeansAudioQuality.current,
                enableUnblock: true,
                strict: strict,
                excludedHosts: excludedHosts
            )
            await MainActor.run {
                guard generation == self.loadGeneration,
                      self.currentSong?.identityKey == song.identityKey else { return }
                if let resolved {
                    let notice = self.thirdPartyVIPNotice(for: song, sourceTitle: resolved.sourceTitle)
                    self.setupPlayer(
                        url: resolved.url,
                        thirdPartyVIPNotice: notice,
                        resumeAt: resume,
                        isThirdParty: true
                    )
                    BeansLogger.shared.log("第三方播放地址重试成功：\(song.name)｜域名=\(resolved.url.host ?? "?")", level: .info)
                } else if let urlString, let url = URL(string: urlString) {
                    self.setupPlayer(url: url, resumeAt: resume)
                    BeansLogger.shared.log("第三方播放地址重试转网易云成功：\(song.name)｜域名=\(url.host ?? "?")", level: .info)
                } else {
                    self.loadFailed = true
                    self.isBuffering = false
                    self.isPlaying = false
                    BeansLogger.shared.log(
                        "第三方播放地址重试未命中：歌曲=\(song.name)｜已排除域名=\(excludedHosts.sorted().joined(separator: ","))",
                        level: .debug
                    )
                }
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
              defaults.object(forKey: "beans.enableUnblock") as? Bool ?? true else { return false }

        qqThirdPartyFallbackSongKey = song.identityKey
        let generation = loadGeneration
        let resume = progress
        let strict = shouldLockOfficialOnly(song)
        BeansLogger.shared.log(
            "QQ 官方地址实际不可播放，切换第三方解析：歌曲=\(song.name)｜系统=\(UIDevice.current.systemVersion)",
            level: .debug
        )
        Task {
            let (urlString, resolved) = await self.qqFallback(song: song, quality: BeansAudioQuality.current, enableUnblock: true, strict: strict)
            await MainActor.run {
                guard generation == self.loadGeneration,
                      self.currentSong?.identityKey == song.identityKey else { return }
                if let resolved {
                    let notice = self.thirdPartyVIPNotice(for: song, sourceTitle: resolved.sourceTitle)
                    self.setupPlayer(
                        url: resolved.url,
                        thirdPartyVIPNotice: notice,
                        resumeAt: resume,
                        isThirdParty: true
                    )
                    BeansLogger.shared.log(
                        "QQ 官方失败后第三方切换成功：\(song.name)｜域名=\(resolved.url.host ?? "?")",
                        level: .info
                    )
                } else if let urlString, let url = URL(string: urlString) {
                    self.setupPlayer(url: url, resumeAt: resume)
                    BeansLogger.shared.log(
                        "QQ 官方失败后网易云同名切换成功：\(song.name)｜域名=\(url.host ?? "?")",
                        level: .info
                    )
                } else {
                    self.loadFailed = true
                    self.isBuffering = false
                    self.isPlaying = false
                    BeansLogger.shared.log("QQ 官方失败后完整兜底仍未命中：\(song.name)", level: .debug)
                }
            }
        }
        return true
    }

    private func setupPlayer(
        url: URL,
        thirdPartyVIPNotice: ThirdPartyVIPNotice? = nil,
        resumeAt: Double = 0,
        isThirdParty: Bool = false
    ) {
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
                "Origin": "https://y.qq.com",
            ]
            let cookie = QQMusicAuth.shared.cookieHeader
            playbackHeaders["Cookie"] = cookie.isEmpty ? "uin=0; qqmusic_fromtag=66" : cookie
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
        player.rate = Float(rate)
        self.player = player
        playbackConfirmed = false
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self, self.player === player, item.status == .failed else { return }
            self.logPlaybackFailure(
                reason: "AVPlayerItem.status.failed",
                item: item,
                url: url,
                isThirdParty: isThirdParty,
                playbackHeaders: playbackHeaders
            )
            if isThirdParty && self.retryThirdPartyIfNeeded(excludingHost: url.host) { return }
            if !isThirdParty && self.fallbackQQToThirdPartyIfNeeded() { return }
            if self.retryKugouAtStandardIfNeeded(error: item.error) { return }
            self.loadFailed = true
            self.isBuffering = false
            self.isPlaying = false
        }
        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self, self.player === player else { return }
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
        if resumeAt > 0.5 {
            let seekTime = CMTime(seconds: resumeAt, preferredTimescale: 600)
            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
            progress = resumeAt
        }
        player.playImmediately(atRate: Float(rate))
        isPlaying = true
        isBuffering = false
        loadFailed = false
        // 修复：播放次数原先在 loadCurrent 里预计数，URL 加载失败/手动重试也会 +1，
        // 导致统计异常；改为真正开始播放时计数，且同一首歌同一会话只计一次。
        if let song = currentSong, lastCountedSongID != song.identityKey {
            bumpPlayCount(song)
            lastCountedSongID = song.identityKey
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self, let player = self.player else { return }
            if time.seconds.isFinite {
                if abs(time.seconds - self.lastPublishedProgress) >= 0.18 {
                    self.lastPublishedProgress = time.seconds
                    self.progress = time.seconds
                    if abs(time.seconds - self.lastPersistedProgress) >= 2.0 {
                        self.lastPersistedProgress = time.seconds
                        self.savePersistedPlaybackState()
                    }
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
            self?.logPlaybackFailure(
                reason: "AVPlayerItemFailedToPlayToEndTime",
                item: item,
                url: url,
                isThirdParty: isThirdParty,
                playbackHeaders: playbackHeaders
            )
            if !isThirdParty && self?.fallbackQQToThirdPartyIfNeeded() == true { return }
            if isThirdParty && self?.retryThirdPartyIfNeeded(excludingHost: url.host) == true { return }
            if self?.retryKugouAtStandardIfNeeded(error: item.error) == true { return }
            self?.loadFailed = true
            self?.isBuffering = false
        }
        updateNowPlaying()
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
        playbackConfirmed = false
        pendingThirdPartyVIPNotice = nil
        lastPublishedProgress = -1
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
            if mixesWithOthers {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            } else {
                try session.setCategory(.playback, mode: .default)
            }
            try session.setActive(true)
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
        sessionConfigured = false
        configureAudioSession()
        if isPlaying, player?.timeControlStatus != .playing {
            player?.playImmediately(atRate: Float(rate))
        }
    }

    // MARK: - 来电/中断处理

    private func observeInterruptions() {
        guard !interruptionObserverInstalled else { return }
        interruptionObserverInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            // 开启「与其他音频同时播放」时，不被其他 App 音频中断，保持继续播放
            guard !mixesWithOthers else { return }
            player?.pause()
            isPlaying = false
        case .ended:
            // 中断结束后系统可能停用了音频会话，重新激活避免无声
            sessionConfigured = false
            configureAudioSession()
            if wasPlayingBeforeInterruption {
                player?.playImmediately(atRate: Float(rate))
                isPlaying = true
            }
        @unknown default:
            break
        }
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
        guard let song = currentSong else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyArtist: song.artists,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: max(duration, song.duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0.0,
        ]
        if let artworkURL = song.coverURL {
            let artworkKey = song.identityKey + "|" + artworkURL.absoluteString
            if let cached = Self.nowPlayingArtworkCache.object(forKey: artworkURL as NSURL) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cached.size) { _ in cached }
            } else if lastNowPlayingArtworkKey != artworkKey {
                lastNowPlayingArtworkKey = artworkKey
                Task {
                    if let data = try? Data(contentsOf: artworkURL), let image = UIImage(data: data) {
                        Self.nowPlayingArtworkCache.setObject(image, forKey: artworkURL as NSURL)
                        var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                    }
                }
            }
        } else {
            lastNowPlayingArtworkKey = nil
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
            self?.player?.playImmediately(atRate: Float(self?.rate ?? 1.0))
            self?.isPlaying = true
            self?.updateNowPlaying()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.isPlaying = false
            self?.updateNowPlaying()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    // MARK: - 与其他音频同时播放

    /// 与其他 App 音频混合播放。默认关闭，让系统把 Beans 作为主播放 App 显示到锁屏/灵动岛。
    var mixesWithOthers: Bool {
        get { defaults.object(forKey: audioMixKey) as? Bool ?? false }
        set {
            defaults.set(newValue, forKey: audioMixKey)
            sessionConfigured = false
            configureAudioSession()
        }
    }

}
