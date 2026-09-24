import Foundation
import QuartzCore

struct CachedPlayURLFailure {
    let error: BiliAPIError
    let expiresAt: CFTimeInterval
}

nonisolated struct PendingPlayURLRequestKey: Hashable, Sendable {
    let cacheKey: PlayURLCacheKey
    let scope: PlayURLCacheLoginScope
}

nonisolated struct PendingPlayURLRequest: Sendable {
    let id: UUID
    let task: Task<PlayURLData, Error>
}

nonisolated struct PendingPlayURLStageRequest: Sendable {
    let id: UUID
    let task: Task<PlayURLData, Error>
}

struct CachedDanmaku {
    let items: [DanmakuItem]
    let storedAt: CFTimeInterval
}

actor BiliAPIClientState {
    private struct PersistedWBIKeys: Codable {
        let keys: WBIKeys
        let storedAt: Date
    }

    private static let persistedWBIKeysKey = "cc.bili.persisted-wbi-keys.v1"
    private let playURLFailureCacheLimit = 96
    private let danmakuCacheLimit = 12
    private let danmakuCacheTTL: CFTimeInterval = 30 * 60
    private var cachedWBIKeys: WBIKeys?
    private var cachedWBIKeysDate: Date?
    private var wbiKeysTask: Task<WBIKeys, Error>?
    private var navTask: Task<NavUserInfo, Error>?
    private var videoListTasks: [String: Task<[VideoItem], Error>] = [:]
    private var videoDetailTasks: [String: Task<VideoItem, Error>] = [:]
    private var uploaderProfileTasks: [Int: Task<UploaderProfile, Error>] = [:]
    private var appRecommendFeedIndex: Int?
    private let startupWBIHealth = StartupWBIHealthStore()
    private let startupWBIRouteHints = StartupWBIRouteHintStore()
    private var playURLFailureCache: [String: CachedPlayURLFailure] = [:]
    private var playURLRequestTasks: [PendingPlayURLRequestKey: PendingPlayURLRequest] = [:]
    private var playURLStageTasks: [String: PendingPlayURLStageRequest] = [:]
    private var danmakuCache: [Int: CachedDanmaku] = [:]

    func freshCachedWBIKeys() -> WBIKeys? {
        guard let keys = cachedWBIKeys,
            let date = cachedWBIKeysDate,
            Date().timeIntervalSince(date) < 12 * 60 * 60
        else {
            if let persisted = persistedWBIKeys() {
                cachedWBIKeys = persisted.keys
                cachedWBIKeysDate = persisted.storedAt
                return persisted.keys
            }
            return nil
        }
        return keys
    }

    func storeWBIKeys(_ keys: WBIKeys) {
        cachedWBIKeys = keys
        cachedWBIKeysDate = Date()
        wbiKeysTask = nil
        persistWBIKeys(keys)
    }

    func clearWBIKeys() {
        cachedWBIKeys = nil
        cachedWBIKeysDate = nil
        wbiKeysTask = nil
        UserDefaults.standard.removeObject(forKey: Self.persistedWBIKeysKey)
    }

    private func persistedWBIKeys() -> PersistedWBIKeys? {
        guard let data = UserDefaults.standard.data(forKey: Self.persistedWBIKeysKey),
            let persisted = try? JSONDecoder().decode(PersistedWBIKeys.self, from: data),
            Date().timeIntervalSince(persisted.storedAt) < 12 * 60 * 60
        else { return nil }
        return persisted
    }

    private func persistWBIKeys(_ keys: WBIKeys) {
        let persisted = PersistedWBIKeys(keys: keys, storedAt: Date())
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistedWBIKeysKey)
    }

    func wbiKeysFetchTask() -> Task<WBIKeys, Error>? {
        wbiKeysTask
    }

    func setWBIKeysFetchTask(_ task: Task<WBIKeys, Error>) {
        wbiKeysTask = task
    }

    func clearWBIKeysFetchTask() {
        wbiKeysTask = nil
    }

    func navUserTask() -> Task<NavUserInfo, Error>? {
        navTask
    }

    func setNavUserTask(_ task: Task<NavUserInfo, Error>) {
        navTask = task
    }

    func clearNavUserTask() {
        navTask = nil
    }

    func videoListTask(for key: String) -> Task<[VideoItem], Error>? {
        videoListTasks[key]
    }

    func setVideoListTask(_ task: Task<[VideoItem], Error>, for key: String) {
        videoListTasks[key] = task
    }

    func clearVideoListTask(for key: String) {
        videoListTasks[key] = nil
    }

    func clearHomeRecommendState() {
        appRecommendFeedIndex = nil
        videoListTasks = videoListTasks.filter { key, _ in
            !key.hasPrefix("recommend|")
        }
    }

    func appRecommendFeedIndex(defaulting defaultIndex: Int) -> Int {
        appRecommendFeedIndex ?? defaultIndex
    }

    func setAppRecommendFeedIndex(_ index: Int?) {
        guard let index, index > 0 else {
            appRecommendFeedIndex = nil
            return
        }
        appRecommendFeedIndex = index
    }

    func videoDetailTask(for bvid: String) -> Task<VideoItem, Error>? {
        videoDetailTasks[bvid]
    }

    func setVideoDetailTask(_ task: Task<VideoItem, Error>, for bvid: String) {
        videoDetailTasks[bvid] = task
    }

    func clearVideoDetailTask(for bvid: String) {
        videoDetailTasks[bvid] = nil
    }

    func clearVideoDetailTasks(containing bvid: String) {
        let keys = videoDetailTasks.keys.filter { $0.hasPrefix("bvid:\(bvid)|") }
        for key in keys {
            videoDetailTasks[key]?.cancel()
            videoDetailTasks[key] = nil
        }
    }

    func uploaderProfileTask(for mid: Int) -> Task<UploaderProfile, Error>? {
        uploaderProfileTasks[mid]
    }

    func setUploaderProfileTask(_ task: Task<UploaderProfile, Error>, for mid: Int) {
        uploaderProfileTasks[mid] = task
    }

    func clearUploaderProfileTask(for mid: Int) {
        uploaderProfileTasks[mid] = nil
    }

    func startupWBISuppressionStatus() async -> StartupWBISuppressionStatus? {
        await startupWBIHealth.suppressionStatus()
    }

    func recordStartupWBISuccess() async -> Bool {
        await startupWBIHealth.recordSuccess()
    }

    func recordStartupWBIFailure(reason: String) async -> StartupWBIHealthUpdate {
        await startupWBIHealth.recordFailure(reason: reason)
    }

    func startupWBIRouteHint(for key: StartupWBIRouteHintKey) async -> StartupWBIRouteHint? {
        await startupWBIRouteHints.hint(for: key)
    }

    func storeStartupWBIRouteHint(
        _ hint: StartupWBIRouteHint,
        for key: StartupWBIRouteHintKey
    ) async {
        await startupWBIRouteHints.store(hint, for: key)
    }

    func pendingPlayURLRequest(for key: PendingPlayURLRequestKey) -> PendingPlayURLRequest? {
        playURLRequestTasks[key]
    }

    func insertPendingPlayURLRequestIfAbsent(
        _ request: PendingPlayURLRequest,
        for key: PendingPlayURLRequestKey
    ) -> PendingPlayURLRequest? {
        if let existing = playURLRequestTasks[key] {
            return existing
        }
        playURLRequestTasks[key] = request
        return nil
    }

    func clearPendingPlayURLRequest(for key: PendingPlayURLRequestKey, id: UUID) {
        guard playURLRequestTasks[key]?.id == id else { return }
        playURLRequestTasks[key] = nil
    }

    func playURLStageTask(for key: String) -> PendingPlayURLStageRequest? {
        playURLStageTasks[key]
    }

    func insertPlayURLStageTaskIfAbsent(
        _ request: PendingPlayURLStageRequest,
        for key: String
    ) -> PendingPlayURLStageRequest? {
        if let existing = playURLStageTasks[key] {
            return existing
        }
        playURLStageTasks[key] = request
        return nil
    }

    func clearPlayURLStageTask(for key: String, id: UUID) {
        guard playURLStageTasks[key]?.id == id else { return }
        playURLStageTasks[key] = nil
    }

    func clearPlayURLFailuresAndTasks(containing bvid: String) async {
        guard !bvid.isEmpty else { return }
        await startupWBIRouteHints.clear(containing: bvid)
        let failureKeys = playURLFailureCache.keys.filter { $0.contains("|\(bvid)|") }
        for key in failureKeys {
            playURLFailureCache[key] = nil
        }
        let taskKeys = playURLStageTasks.keys.filter { $0.contains("|\(bvid)|") }
        for key in taskKeys {
            playURLStageTasks[key]?.task.cancel()
            playURLStageTasks[key] = nil
        }
        let requestKeys = playURLRequestTasks.keys.filter { $0.cacheKey.bvid == bvid }
        for key in requestKeys {
            playURLRequestTasks[key]?.task.cancel()
            playURLRequestTasks[key] = nil
        }
    }

    func clearAllPlayURLFailuresAndTasks() async {
        await startupWBIRouteHints.clear()
        playURLFailureCache.removeAll()
        for request in playURLStageTasks.values {
            request.task.cancel()
        }
        playURLStageTasks.removeAll()
        for request in playURLRequestTasks.values {
            request.task.cancel()
        }
        playURLRequestTasks.removeAll()
    }

    func cachedDanmaku(for cid: Int) -> [DanmakuItem]? {
        let now = CACurrentMediaTime()
        guard let cached = danmakuCache[cid] else { return nil }
        guard now - cached.storedAt < danmakuCacheTTL else {
            danmakuCache[cid] = nil
            return nil
        }
        return cached.items
    }

    func storeDanmaku(_ items: [DanmakuItem], for cid: Int) {
        danmakuCache[cid] = CachedDanmaku(items: items, storedAt: CACurrentMediaTime())
        trimDanmakuCacheIfNeeded()
    }

    func cancelPlayURLStage(_ key: String) {
        playURLStageTasks[key]?.task.cancel()
        playURLStageTasks[key] = nil
    }

    func cachedPlayURLFailure(for key: String) -> BiliAPIError? {
        let now = CACurrentMediaTime()
        if let cached = playURLFailureCache[key] {
            if cached.expiresAt > now {
                return cached.error
            }
            playURLFailureCache[key] = nil
        }
        trimExpiredPlayURLFailures(now: now)
        return nil
    }

    func storePlayURLFailure(_ error: Error, for key: String) {
        guard let cacheableError = BiliAPIClient.cacheablePlayURLFailure(error) else { return }
        let now = CACurrentMediaTime()
        playURLFailureCache[key] = CachedPlayURLFailure(
            error: cacheableError,
            expiresAt: now + BiliAPIClient.playURLFailureTTL(for: cacheableError)
        )
        trimPlayURLFailureCacheIfNeeded(now: now)
    }

    private func trimExpiredPlayURLFailures(now: CFTimeInterval = CACurrentMediaTime()) {
        playURLFailureCache = playURLFailureCache.filter { $0.value.expiresAt > now }
    }

    private func trimPlayURLFailureCacheIfNeeded(now: CFTimeInterval = CACurrentMediaTime()) {
        trimExpiredPlayURLFailures(now: now)
        guard playURLFailureCache.count > playURLFailureCacheLimit else { return }
        let overflow = playURLFailureCache.count - playURLFailureCacheLimit
        let expiredKeys =
            playURLFailureCache
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(overflow)
            .map(\.key)
        for key in expiredKeys {
            playURLFailureCache[key] = nil
        }
    }

    private func trimDanmakuCacheIfNeeded(now: CFTimeInterval = CACurrentMediaTime()) {
        danmakuCache = danmakuCache.filter { now - $0.value.storedAt < danmakuCacheTTL }
        guard danmakuCache.count > danmakuCacheLimit else { return }
        let overflow = danmakuCache.count - danmakuCacheLimit
        let oldestKeys =
            danmakuCache
            .sorted { $0.value.storedAt < $1.value.storedAt }
            .prefix(overflow)
            .map(\.key)
        for key in oldestKeys {
            danmakuCache[key] = nil
        }
    }
}
