import Combine
import SwiftUI
import CiliCiliKit

@MainActor
final class BilibiliCiliCiliBridge {
    static let shared = BilibiliCiliCiliBridge()
    private var subscriptions = Set<AnyCancellable>()
    private weak var player: PlayerManager?

    func configure(player: PlayerManager) {
        self.player = player
        guard subscriptions.isEmpty else { return }
        let runtime = CiliCiliRuntime.shared
        runtime.onPlaybackActivation = { [weak self] in self?.player?.pauseForBilibiliVideo() }
        runtime.onVideoListenModeChange = { [weak self] request, enabled, resumeAt, shouldResume in
            self?.handleVideoListenModeChange(
                request: request,
                enabled: enabled,
                resumeAt: resumeAt,
                shouldResume: shouldResume
            )
        }
        runtime.onSessionChange = { cookie, name, id, avatar in
            try BilibiliAuth.shared.acceptCiliCiliSession(cookie: cookie, name: name, id: id, avatar: avatar)
        }
        synchronizeAccount()
        runtime.$isVideoDetailActive.removeDuplicates().sink { active in
            if active { BilibiliPresentationState.shared.enterVideo("cilicili-module") }
            else { BilibiliPresentationState.shared.leaveVideo("cilicili-module") }
        }.store(in: &subscriptions)
        runtime.$isLiveRoomActive.removeDuplicates().sink { active in
            if active { BilibiliPresentationState.shared.enterLive("cilicili-live") }
            else { BilibiliPresentationState.shared.leaveLive("cilicili-live") }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .beansBilibiliLoginDidUpdate).sink { [weak self] _ in
            self?.synchronizeAccount()
        }.store(in: &subscriptions)
        player.$isPlaying.removeDuplicates().filter { $0 }.sink { _ in
            runtime.stopPlaybackForMusic()
        }.store(in: &subscriptions)
    }

    private func handleVideoListenModeChange(
        request: CiliCiliVideoListenRequest,
        enabled: Bool,
        resumeAt: TimeInterval,
        shouldResume: Bool
    ) {
        guard let player else { return }
        guard enabled else {
            player.pauseForBilibiliVideo()
            return
        }

        let bilibiliID = request.cid.map { request.bvid + ":" + String($0) } ?? request.bvid
        let song = Song(
            id: request.aid ?? 0,
            name: request.title,
            artists: request.artist.isEmpty ? "哔哩哔哩" : request.artist,
            album: "哔哩哔哩视频",
            coverURL: request.coverURL.flatMap(URL.init(string:)),
            duration: request.duration,
            source: .bilibili,
            bilibiliID: bilibiliID
        )
        player.playBilibiliAudio(song, resumeAt: resumeAt, shouldResume: shouldResume)
        guard shouldResume else { return }

        // Beans 的播放器按钮不经过 CiliCili 的详情页控件。把当前上下文的
        // 下一批视频补进同一个 Beans 队列，才能让“下一首”继续按 UP 主/相关推荐
        // 前进，而不是因为外部播放器队列只有一首而停住。
        let api = BilibiliAPI.shared
        Task { @MainActor [weak player] in
            do {
                let candidates: [BilibiliFeedVideo]
                if let ownerID = request.ownerID, ownerID > 0 {
                    let owner = Artist(id: String(ownerID), name: request.artist, coverURL: nil, source: .bilibili)
                    candidates = try await api.upVideos(owner, page: 1).items
                } else {
                    candidates = try await api.relatedVideos(aid: String(request.aid ?? 0))
                }
                let additions = candidates.compactMap { item -> Song? in
                    let bvid = item.song.bilibiliID?.split(separator: ":").first.map(String.init)
                    guard bvid != request.bvid else { return nil }
                    return item.song
                }
                player?.append(songs: additions)
            } catch {
                BeansLogger.shared.log("听视频队列预加载失败：\(error.localizedDescription)", level: .debug)
            }
        }
    }

    private func synchronizeAccount() {
        let auth = BilibiliAuth.shared
        CiliCiliRuntime.shared.synchronizeLegacySession(
            cookie: auth.cookieHeader, name: auth.nickname, userID: auth.accountID,
            avatar: auth.avatarURL?.absoluteString
        )
    }
}

extension BilibiliNativeRoute {
    var ciliCiliRoute: CiliCiliRoute? {
        switch self {
        case .video(let song):
            let parts = (song.bilibiliID ?? "").split(separator: ":", maxSplits: 1)
            return .video(bvid: parts.first.map(String.init) ?? "", title: song.name,
                          cover: song.coverURL?.absoluteString, cid: parts.count > 1 ? Int(parts[1]) : nil)
        case .up(let artist):
            return .uploader(mid: Int(artist.id) ?? 0, name: artist.name, avatar: artist.coverURL?.absoluteString)
        case .live(let room): return .live(roomID: Int(room.id) ?? 0)
        case .collection(let item):
            return .collection(id: Int(item.number) ?? 0, isSeries: item.kind == .series,
                               ownerID: Int(item.ownerID) ?? 0, ownerName: item.ownerName, title: item.title)
        case .account: return .account
        case .playlist: return nil
        }
    }
}
