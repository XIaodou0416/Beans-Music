import Foundation

struct VideoListenPlaybackSessionState: Equatable, Sendable {
    let audioPreferenceKey: String?
    let wantsPlayback: Bool
}

@MainActor
final class VideoListenPlaybackSessionStore {
    static let shared = VideoListenPlaybackSessionStore()

    private struct Entry {
        let state: VideoListenPlaybackSessionState
        let updatedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let maximumEntryCount: Int

    init(maximumEntryCount: Int = 12) {
        self.maximumEntryCount = max(maximumEntryCount, 1)
    }

    func state(for video: VideoItem) -> VideoListenPlaybackSessionState? {
        guard let key = Self.contentKey(for: video) else { return nil }
        return entries[key]?.state
    }

    func save(_ state: VideoListenPlaybackSessionState, for video: VideoItem) {
        guard let key = Self.contentKey(for: video) else { return }
        entries[key] = Entry(state: state, updatedAt: Date())
        trimIfNeeded()
    }

    func removeState(for video: VideoItem) {
        guard let key = Self.contentKey(for: video) else { return }
        entries.removeValue(forKey: key)
    }

    func removeAll() {
        entries.removeAll()
    }

    nonisolated static func contentKey(for video: VideoItem) -> String? {
        if let seasonID = video.pgcSeasonID, seasonID > 0 {
            return "pgc-season:\(seasonID)"
        }
        if video.isPGCEpisode, let episodeID = video.pgcEpisodeID, episodeID > 0 {
            return "pgc-episode:\(episodeID)"
        }

        let bvid = video.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bvid.isEmpty {
            return "ugc:\(bvid.lowercased())"
        }
        if let aid = video.aid, aid > 0 {
            return "aid:\(aid)"
        }
        return nil
    }

    private func trimIfNeeded() {
        guard entries.count > maximumEntryCount else { return }
        let overflow = entries.count - maximumEntryCount
        let oldestKeys = entries
            .sorted { $0.value.updatedAt < $1.value.updatedAt }
            .prefix(overflow)
            .map(\.key)
        oldestKeys.forEach { entries.removeValue(forKey: $0) }
    }
}

struct VideoListenAudioInterruptionState: Equatable {
    private(set) var isActive = false
    private(set) var shouldResume = false

    @discardableResult
    mutating func begin(hadPlaybackIntent: Bool) -> Bool {
        isActive = true
        shouldResume = hadPlaybackIntent
        return hadPlaybackIntent
    }

    mutating func cancelAutomaticResume() {
        guard isActive else { return }
        shouldResume = false
    }

    mutating func end(systemAllowsResume: Bool) -> Bool {
        let resumesPlayback = isActive && shouldResume && systemAllowsResume
        reset()
        return resumesPlayback
    }

    mutating func reset() {
        isActive = false
        shouldResume = false
    }
}

enum VideoListenSleepTimerCountdownFormatter {
    static func text(deadline: Date, now: Date = Date()) -> String {
        let remainingSeconds = max(Int(ceil(deadline.timeIntervalSince(now))), 0)
        let hours = remainingSeconds / 3_600
        let minutes = (remainingSeconds % 3_600) / 60
        let seconds = remainingSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

enum VideoListenPlaybackOrder: String, CaseIterable, Identifiable, Sendable {
    case sequential
    case repeatCurrent
    case stopAfterCurrent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential:
            return "顺序播放"
        case .repeatCurrent:
            return "单集循环"
        case .stopAfterCurrent:
            return "播完暂停"
        }
    }

    var subtitle: String {
        switch self {
        case .sequential:
            return "播完后自动进入下一分 P 或下一集"
        case .repeatCurrent:
            return "当前内容播完后从头继续"
        case .stopAfterCurrent:
            return "当前内容播完后停止，不自动续播"
        }
    }

    var systemImage: String {
        switch self {
        case .sequential:
            return "list.number"
        case .repeatCurrent:
            return "repeat.1"
        case .stopAfterCurrent:
            return "stop.circle"
        }
    }
}

enum VideoListenPlaybackEndAction: Equatable {
    case advance
    case replayCurrent
    case pause
}

enum VideoListenPlaybackEndResolver {
    static func action(
        playbackOrder: VideoListenPlaybackOrder,
        sleepTimerOption: VideoListenSleepTimerOption
    ) -> VideoListenPlaybackEndAction {
        if sleepTimerOption == .endOfCurrent {
            return .pause
        }

        switch playbackOrder {
        case .sequential:
            return .advance
        case .repeatCurrent:
            return .replayCurrent
        case .stopAfterCurrent:
            return .pause
        }
    }
}

enum VideoListenSleepTimerOption: String, CaseIterable, Identifiable, Sendable {
    case off
    case minutes15
    case minutes30
    case minutes45
    case minutes60
    case endOfCurrent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "关闭"
        case .minutes15:
            return "15 分钟"
        case .minutes30:
            return "30 分钟"
        case .minutes45:
            return "45 分钟"
        case .minutes60:
            return "60 分钟"
        case .endOfCurrent:
            return "播完当前后暂停"
        }
    }

    var systemImage: String {
        switch self {
        case .off:
            return "timer"
        case .minutes15, .minutes30, .minutes45, .minutes60:
            return "timer.circle"
        case .endOfCurrent:
            return "moon.zzz"
        }
    }

    var durationMinutes: Int? {
        switch self {
        case .minutes15:
            return 15
        case .minutes30:
            return 30
        case .minutes45:
            return 45
        case .minutes60:
            return 60
        case .off, .endOfCurrent:
            return nil
        }
    }
}

enum VideoListenQueueSource: Hashable {
    case currentVideo
    case officialListener(anchorAID: Int, sortOrder: VideoListenPlaylistSortOrder)
    case uploader(mid: Int)
    case pgcSeason(id: Int?)
    case related(anchorBVID: String)

    var title: String {
        switch self {
        case .currentVideo:
            return "当前视频"
        case .officialListener:
            return "B站官方列表"
        case .uploader:
            return "UP 主投稿"
        case .pgcSeason:
            return "剧集列表"
        case .related:
            return "相关推荐"
        }
    }
}

enum VideoListenQueuePaginationDirection: String, Sendable {
    case previous
    case next
}

struct VideoListenQueueSession: Equatable {
    var source: VideoListenQueueSource
    var videos: [VideoItem]
    var nextPage: Int
    var nextCursor: UploaderVideoPageCursor?
    var listenerPreviousToken: String?
    var listenerNextToken: String?
    var hasMore: Bool
    var isLoadingInitial: Bool
    var isLoadingMore: Bool
    var errorMessage: String?
    var generation: UUID

    init(seedVideo: VideoItem) {
        source = .currentVideo
        videos = [seedVideo]
        nextPage = 1
        nextCursor = nil
        listenerPreviousToken = nil
        listenerNextToken = nil
        hasMore = false
        isLoadingInitial = false
        isLoadingMore = false
        errorMessage = nil
        generation = UUID()
    }

    mutating func beginInitialLoad(
        source: VideoListenQueueSource,
        anchor: VideoItem
    ) -> UUID {
        let generation = UUID()
        self.source = source
        videos = [anchor]
        nextPage = 1
        nextCursor = nil
        listenerPreviousToken = nil
        listenerNextToken = nil
        hasMore = false
        isLoadingInitial = true
        isLoadingMore = false
        errorMessage = nil
        self.generation = generation
        return generation
    }

    @discardableResult
    mutating func finishInitialLoad(
        videos: [VideoItem],
        anchor: VideoItem,
        source: VideoListenQueueSource,
        nextPage: Int,
        nextCursor: UploaderVideoPageCursor?,
        hasMore: Bool,
        listenerPreviousToken: String? = nil,
        listenerNextToken: String? = nil,
        generation: UUID
    ) -> Bool {
        guard self.generation == generation else { return false }
        var resolvedVideos = videos
        if !resolvedVideos.contains(where: {
            VideoListenQueueBuilder.representsSameVideo($0, anchor)
        }) {
            resolvedVideos.insert(anchor, at: 0)
        }
        self.source = source
        self.videos = Self.uniqueVideos(resolvedVideos, anchor: anchor)
        self.nextPage = nextPage
        self.nextCursor = nextCursor
        self.listenerPreviousToken = listenerPreviousToken
        self.listenerNextToken = listenerNextToken
        self.hasMore = hasMore || listenerPreviousToken != nil || listenerNextToken != nil
        isLoadingInitial = false
        isLoadingMore = false
        errorMessage = nil
        return true
    }

    mutating func failInitialLoad(_ message: String, generation: UUID) {
        guard self.generation == generation else { return }
        isLoadingInitial = false
        isLoadingMore = false
        hasMore = false
        listenerPreviousToken = nil
        listenerNextToken = nil
        errorMessage = message
    }

    mutating func beginLoadMore() -> UUID? {
        guard hasMore, !isLoadingInitial, !isLoadingMore else { return nil }
        isLoadingMore = true
        errorMessage = nil
        return generation
    }

    @discardableResult
    mutating func finishLoadMore(
        videos: [VideoItem],
        nextPage: Int,
        nextCursor: UploaderVideoPageCursor?,
        hasMore: Bool,
        listenerDirection: VideoListenQueuePaginationDirection? = nil,
        listenerPreviousToken: String? = nil,
        listenerNextToken: String? = nil,
        generation: UUID
    ) -> Bool {
        guard self.generation == generation else { return false }
        if listenerDirection == .previous {
            let newVideos = Self.uniqueVideos(videos, anchor: nil).filter { video in
                !self.videos.contains(where: {
                    VideoListenQueueBuilder.representsSameVideo($0, video)
                })
            }
            self.videos = newVideos + self.videos
        } else {
            self.videos = Self.uniqueVideos(self.videos + videos, anchor: nil)
        }
        self.nextPage = nextPage
        self.nextCursor = nextCursor
        switch listenerDirection {
        case .previous:
            self.listenerPreviousToken = listenerPreviousToken
        case .next:
            self.listenerNextToken = listenerNextToken
        case nil:
            self.listenerPreviousToken = nil
            self.listenerNextToken = nil
        }
        self.hasMore = listenerDirection == nil
            ? hasMore
            : self.listenerPreviousToken != nil || self.listenerNextToken != nil
        isLoadingMore = false
        errorMessage = nil
        return true
    }

    mutating func failLoadMore(_ message: String, generation: UUID) {
        guard self.generation == generation else { return }
        isLoadingMore = false
        errorMessage = message
    }

    mutating func cancelLoading(generation: UUID) {
        guard self.generation == generation else { return }
        isLoadingInitial = false
        isLoadingMore = false
    }

    mutating func replaceVideo(with video: VideoItem) {
        if let index = videos.firstIndex(where: {
            VideoListenQueueBuilder.representsSameVideo($0, video)
        }) {
            videos[index] = video
        } else {
            videos.append(video)
        }
    }

    func video(
        relativeTo current: VideoItem,
        direction: VideoListenAdvanceDirection
    ) -> VideoItem? {
        guard let index = videos.firstIndex(where: {
            VideoListenQueueBuilder.representsSameVideo($0, current)
        }) else { return nil }
        let targetIndex = direction == .next ? index + 1 : index - 1
        guard videos.indices.contains(targetIndex) else { return nil }
        return videos[targetIndex]
    }

    private static func uniqueVideos(
        _ videos: [VideoItem],
        anchor: VideoItem?
    ) -> [VideoItem] {
        var result = [VideoItem]()
        for video in videos {
            guard !VideoListenQueueBuilder.contentKey(for: video).isEmpty else { continue }
            guard !result.contains(where: {
                VideoListenQueueBuilder.representsSameVideo($0, video)
            }) else { continue }
            if let anchor, VideoListenQueueBuilder.representsSameVideo(video, anchor) {
                result.append(anchor)
            } else {
                result.append(video)
            }
        }
        return result
    }
}

enum VideoListenQueueTarget: Hashable {
    case page(VideoPage)
    case video(VideoItem)
    case episode(VideoItem)
}

struct VideoListenQueueEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let isCurrent: Bool
    let target: VideoListenQueueTarget
}

enum VideoListenQueueBuilder {
    static func entries(
        videos: [VideoItem],
        current detail: VideoItem,
        selectedCID: Int?
    ) -> [VideoListenQueueEntry] {
        let queueVideos: [VideoItem]
        if videos.contains(where: { representsSameVideo($0, detail) }) {
            queueVideos = videos
        } else {
            queueVideos = [detail] + videos
        }

        return queueVideos.flatMap { video in
            let isCurrentVideo = representsSameVideo(video, detail)
            let resolvedVideo = isCurrentVideo ? detail : video
            if isCurrentVideo,
               !detail.isPGCEpisode,
               let pages = detail.pages,
               pages.count > 1 {
                return self.pages(pages, selectedCID: selectedCID)
            }
            return [videoEntry(resolvedVideo, isCurrent: isCurrentVideo)]
        }
    }

    static func pages(_ pages: [VideoPage], selectedCID: Int?) -> [VideoListenQueueEntry] {
        pages.enumerated().map { index, page in
            let pageNumber = page.page ?? index + 1
            let part = page.part?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = part?.isEmpty == false ? part! : "第 \(pageNumber) P"
            return VideoListenQueueEntry(
                id: "page:\(page.cid)",
                title: title,
                subtitle: durationText(page.duration),
                isCurrent: page.cid == selectedCID,
                target: .page(page)
            )
        }
    }

    static func episodes(
        in season: PgcSeasonInfo,
        current detail: VideoItem
    ) -> [VideoListenQueueEntry] {
        season.allPlayableEpisodes.enumerated().compactMap { index, episode in
            guard let video = episode.videoItem(in: season) else { return nil }
            return VideoListenQueueEntry(
                id: "episode:\(episode.id)-\(index)",
                title: episode.displayTitle,
                subtitle: durationText(episode.durationSeconds),
                isCurrent: representsSameVideo(video, detail),
                target: .episode(video)
            )
        }
    }

    static func contentKey(for video: VideoItem) -> String {
        if let episodeID = video.pgcEpisodeID, episodeID > 0 {
            return "episode:\(episodeID)"
        }
        let bvid = video.bvid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !bvid.isEmpty {
            return "bvid:\(bvid)"
        }
        if let aid = video.aid, aid > 0 {
            return "aid:\(aid)"
        }
        return ""
    }

    static func representsSameVideo(_ lhs: VideoItem, _ rhs: VideoItem) -> Bool {
        if let lhsEpisodeID = lhs.pgcEpisodeID,
           lhsEpisodeID > 0,
           let rhsEpisodeID = rhs.pgcEpisodeID,
           rhsEpisodeID > 0 {
            return lhsEpisodeID == rhsEpisodeID
        }
        if let lhsAID = lhs.aid,
           lhsAID > 0,
           let rhsAID = rhs.aid,
           rhsAID > 0 {
            return lhsAID == rhsAID
        }

        let lhsBVID = normalizedBVID(lhs.bvid)
        let rhsBVID = normalizedBVID(rhs.bvid)
        return !lhsBVID.isEmpty && lhsBVID == rhsBVID
    }

    private static func normalizedBVID(_ bvid: String) -> String {
        bvid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func videoEntry(_ video: VideoItem, isCurrent: Bool) -> VideoListenQueueEntry {
        let owner = video.owner?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = [
            owner?.isEmpty == false ? owner : nil,
            durationText(video.duration)
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        let target: VideoListenQueueTarget = video.isPGCEpisode ? .episode(video) : .video(video)
        return VideoListenQueueEntry(
            id: "video:\(contentKey(for: video))",
            title: video.title,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            isCurrent: isCurrent,
            target: target
        )
    }

    private static func durationText(_ duration: Int?) -> String? {
        guard let duration, duration > 0 else { return nil }
        let hours = duration / 3_600
        let minutes = (duration % 3_600) / 60
        let seconds = duration % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
