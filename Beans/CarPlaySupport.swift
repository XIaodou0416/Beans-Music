import CarPlay
import Combine
import Foundation
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        BeansCarPlayCoordinator.shared.didConnect(interfaceController: interfaceController)
    }

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        BeansCarPlayCoordinator.shared.didDisconnect()
    }
}

@MainActor
final class BeansCarPlayCoordinator: NSObject {
    static let shared = BeansCarPlayCoordinator()

    private weak var player: PlayerManager?
    private weak var interfaceController: CPInterfaceController?
    private var cancellables: Set<AnyCancellable> = []
    private var refreshScheduled = false
    private var contentTask: Task<Void, Never>?
    private var contentGeneration = 0

    private var recommendTemplate: CPListTemplate?
    private var curatedTemplate: CPListTemplate?
    private var roamingTemplate: CPListTemplate?
    private var libraryTemplate: CPListTemplate?

    private override init() {
        super.init()
    }

    func configure(player: PlayerManager) {
        guard self.player !== player else {
            scheduleRefresh()
            return
        }

        cancellables.removeAll()
        self.player = player
        player.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleRefresh()
            }
            .store(in: &cancellables)
        scheduleRefresh()
    }

    func didConnect(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        let recommend = CPListTemplate(title: "推荐", sections: [])
        recommend.tabImage = UIImage(systemName: "house")
        recommend.emptyViewTitleVariants = ["暂无推荐内容"]

        let curated = CPListTemplate(title: "精选", sections: [])
        curated.tabImage = UIImage(systemName: "sparkles")
        curated.emptyViewTitleVariants = ["暂无精选歌单"]

        let roaming = CPListTemplate(title: "漫游", sections: [])
        roaming.tabImage = UIImage(systemName: "shuffle")
        roaming.emptyViewTitleVariants = ["暂无漫游歌曲"]

        let library = CPListTemplate(title: "我的", sections: [])
        library.tabImage = UIImage(systemName: "music.note.list")
        library.emptyViewTitleVariants = ["暂无播放记录"]

        recommendTemplate = recommend
        curatedTemplate = curated
        roamingTemplate = roaming
        libraryTemplate = library

        let root = CPTabBarTemplate(templates: [recommend, curated, roaming, library])
        interfaceController.setRootTemplate(root, animated: true, completion: nil)
        reloadRemoteContent()
        scheduleRefresh()
    }

    func didDisconnect() {
        contentTask?.cancel()
        contentTask = nil
        contentGeneration += 1
        interfaceController = nil
        recommendTemplate = nil
        curatedTemplate = nil
        roamingTemplate = nil
        libraryTemplate = nil
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refreshPlayerDrivenTemplates()
        }
    }

    private func refreshPlayerDrivenTemplates() {
        guard interfaceController != nil else { return }
        refreshRecommend()
        refreshLibrary()
        refreshNowPlaying()
    }

    private func reloadRemoteContent() {
        contentTask?.cancel()
        contentGeneration += 1
        let generation = contentGeneration

        contentTask = Task { [weak self] in
            guard let self else { return }

            async let recommendations = NetEaseAPI.shared.recommendedHomePlaylists(loggedIn: false, limit: 12)
            async let curated = (try? await NetEaseAPI.shared.highQualityPlaylists(limit: 18)) ?? []
            async let daily = (try? await NetEaseAPI.shared.dailyRecommend()) ?? []
            async let topLists = (try? await NetEaseAPI.shared.topLists()) ?? []
            async let roaming = (try? await NetEaseAPI.shared.personalFM(limit: 30)) ?? []

            let loadedRecommendations = await recommendations
            let loadedCurated = await curated
            let loadedDaily = await daily
            let loadedTopLists = await topLists
            let loadedRoaming = await roaming

            guard !Task.isCancelled, generation == self.contentGeneration else { return }
            self.updateRecommend(
                playlists: loadedRecommendations,
                daily: loadedDaily,
                topLists: loadedTopLists
            )
            self.updateCurated(playlists: loadedCurated)
            self.updateRoaming(songs: loadedRoaming)
        }
    }

    private func refreshNowPlaying() {
        guard player?.currentSong != nil else { return }
        let template = CPNowPlayingTemplate.shared
        template.isUpNextButtonEnabled = false
        template.isAlbumArtistButtonEnabled = false
    }

    private func refreshRecommend() {
        guard let recommendTemplate, let player else { return }
        var sections: [CPListSection] = []

        if let currentSong = player.currentSong {
            let currentItem = makeTrackItem(
                currentSong,
                tracks: player.queue.isEmpty ? [currentSong] : player.queue,
                startIndex: max(0, player.queue.firstIndex(of: currentSong) ?? 0)
            )
            currentItem.handler = { [weak self] _, completion in
                self?.showNowPlaying()
                completion()
            }
            sections.append(CPListSection(items: [currentItem], header: "正在播放", sectionIndexTitle: nil))
        }

        let queueItem = CPListItem(
            text: "播放队列",
            detailText: player.queue.isEmpty ? "暂无歌曲" : "\(player.queue.count) 首"
        )
        queueItem.setImage(UIImage(systemName: "list.bullet"))
        queueItem.handler = { [weak self] _, completion in
            self?.pushTrackList(title: "播放队列", tracks: player.queue)
            completion()
        }

        let historyItem = CPListItem(
            text: "最近播放",
            detailText: player.history.isEmpty ? "暂无记录" : "\(player.history.count) 首"
        )
        historyItem.setImage(UIImage(systemName: "clock"))
        historyItem.handler = { [weak self] _, completion in
            self?.pushTrackList(title: "最近播放", tracks: player.history)
            completion()
        }

        sections.append(CPListSection(items: [queueItem, historyItem], header: "播放", sectionIndexTitle: nil))
        recommendTemplate.updateSections(sections)
    }

    private func updateRecommend(playlists: [Playlist], daily: [Song], topLists: [TopList]) {
        guard let recommendTemplate else { return }
        var sections: [CPListSection] = []

        if !daily.isEmpty {
            let dailyItem = CPListItem(
                text: "每日推荐",
                detailText: "\(daily.count) 首歌曲"
            )
            dailyItem.setImage(UIImage(systemName: "calendar"))
            dailyItem.handler = { [weak self] _, completion in
                self?.pushTrackList(title: "每日推荐", tracks: daily)
                completion()
            }
            sections.append(CPListSection(items: [dailyItem], header: "Beans Music", sectionIndexTitle: nil))
        }

        if !playlists.isEmpty {
            let items = playlists.map { makePlaylistItem($0) }
            sections.append(CPListSection(items: items, header: "推荐歌单", sectionIndexTitle: nil))
        }

        if !topLists.isEmpty {
            let items = topLists.map { topList in
                let item = CPListItem(text: topList.name, detailText: topList.updateFrequency)
                item.setImage(UIImage(systemName: "chart.bar"))
                item.handler = { [weak self] _, completion in
                    self?.loadTopList(topList)
                    completion()
                }
                setArtwork(for: item, url: topList.coverURL)
                return item
            }
            sections.append(CPListSection(items: items, header: "排行榜", sectionIndexTitle: nil))
        }

        if sections.isEmpty {
            recommendTemplate.updateSections([
                CPListSection(items: [
                    CPListItem(text: "暂无推荐内容", detailText: "请稍后重试")
                ])
            ])
        } else {
            recommendTemplate.updateSections(sections)
        }
    }

    private func updateCurated(playlists: [Playlist]) {
        guard let curatedTemplate else { return }
        if playlists.isEmpty {
            curatedTemplate.updateSections([
                CPListSection(items: [
                    CPListItem(text: "暂无精选歌单", detailText: "请稍后重试")
                ])
            ])
            return
        }

        let items = playlists.map { makePlaylistItem($0) }
        curatedTemplate.updateSections([
            CPListSection(items: items, header: "精选歌单", sectionIndexTitle: nil)
        ])
    }

    private func updateRoaming(songs: [Song]) {
        guard let roamingTemplate else { return }
        if songs.isEmpty {
            let item = CPListItem(text: "暂无漫游歌曲", detailText: "当前无法获取漫游内容")
            item.setImage(UIImage(systemName: "shuffle"))
            roamingTemplate.updateSections([CPListSection(items: [item])])
            return
        }

        let start = CPListItem(text: "开始私人漫游", detailText: "\(songs.count) 首歌曲")
        start.setImage(UIImage(systemName: "play.fill"))
        start.handler = { [weak self] _, completion in
            self?.player?.play(songs: songs, startAt: 0)
            self?.showNowPlaying()
            completion()
        }

        let items = songs.enumerated().map { index, song in
            makeTrackItem(song, tracks: songs, startIndex: index)
        }
        roamingTemplate.updateSections([
            CPListSection(items: [start], header: "漫游播放", sectionIndexTitle: nil),
            CPListSection(items: Array(items.prefix(30)), header: "歌曲", sectionIndexTitle: nil)
        ])
    }

    private func refreshLibrary() {
        guard let libraryTemplate, let player else { return }
        var sections: [CPListSection] = []

        if !player.queue.isEmpty {
            let items = player.queue.enumerated().map { index, song in
                makeTrackItem(song, tracks: player.queue, startIndex: index)
            }
            sections.append(CPListSection(items: items, header: "当前队列", sectionIndexTitle: nil))
        }

        if !player.history.isEmpty {
            let recent = Array(player.history.prefix(30))
            let items = recent.enumerated().map { index, song in
                makeTrackItem(song, tracks: recent, startIndex: index)
            }
            sections.append(CPListSection(items: items, header: "最近播放", sectionIndexTitle: nil))
        }

        if sections.isEmpty {
            sections.append(CPListSection(items: [
                CPListItem(text: "暂无本地播放记录", detailText: "在 Beans Music 播放歌曲后会显示在这里")
            ]))
        }
        libraryTemplate.updateSections(sections)
    }

    private func makePlaylistItem(_ playlist: Playlist) -> CPListItem {
        let detail = playlist.playCount > 0
            ? "\(playlist.creatorName.isEmpty ? "Beans Music" : playlist.creatorName) · \(playlist.playCount) 次播放"
            : (playlist.creatorName.isEmpty ? "歌单" : playlist.creatorName)
        let item = CPListItem(text: playlist.name, detailText: detail)
        item.accessoryType = .disclosureIndicator
        setArtwork(for: item, url: playlist.coverURL)
        item.handler = { [weak self] _, completion in
            self?.pushPlaylistDetail(playlist)
            completion()
        }
        return item
    }

    private func makeTrackItem(_ song: Song, tracks: [Song], startIndex: Int) -> CPListItem {
        let item = CPListItem(text: song.name, detailText: song.artists)
        item.accessoryType = .none
        setArtwork(for: item, url: song.coverURL)
        item.handler = { [weak self] _, completion in
            self?.player?.play(songs: tracks, startAt: startIndex)
            self?.showNowPlaying()
            completion()
        }
        return item
    }

    private func pushTrackList(title: String, tracks: [Song]) {
        guard let interfaceController, !tracks.isEmpty else { return }
        let template = CPListTemplate(title: title, sections: [])
        let items = tracks.enumerated().map { index, song in
            makeTrackItem(song, tracks: tracks, startIndex: index)
        }
        template.updateSections([
            CPListSection(items: items, header: "\(tracks.count) 首", sectionIndexTitle: nil)
        ])
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func pushPlaylistDetail(_ playlist: Playlist) {
        guard let interfaceController else { return }
        let template = CPListTemplate(title: playlist.name, sections: [])
        template.emptyViewTitleVariants = ["正在加载歌单"]
        interfaceController.pushTemplate(template, animated: true, completion: nil)

        Task { [weak self, weak template] in
            do {
                let songs = try await NetEaseAPI.shared.playlistTracks(id: playlist.id)
                guard !songs.isEmpty else {
                    await MainActor.run {
                        template?.updateSections([
                            CPListSection(items: [
                                CPListItem(text: "歌单暂无歌曲", detailText: playlist.playlistDescription)
                            ])
                        ])
                    }
                    return
                }
                await MainActor.run {
                    let items = songs.enumerated().map { index, song in
                        self?.makeTrackItem(song, tracks: songs, startIndex: index)
                    }.compactMap { $0 }
                    template?.updateSections([
                        CPListSection(items: items, header: "\(songs.count) 首", sectionIndexTitle: nil)
                    ])
                }
            } catch {
                await MainActor.run {
                    template?.updateSections([
                        CPListSection(items: [
                            CPListItem(text: "歌单加载失败", detailText: "请稍后重试")
                        ])
                    ])
                }
            }
        }
    }

    private func loadTopList(_ topList: TopList) {
        guard let interfaceController else { return }
        let template = CPListTemplate(title: topList.name, sections: [])
        template.emptyViewTitleVariants = ["正在加载排行榜"]
        interfaceController.pushTemplate(template, animated: true, completion: nil)

        Task { [weak self, weak template] in
            do {
                let songs = try await NetEaseAPI.shared.playlistTracks(id: topList.id)
                await MainActor.run {
                    let items = songs.enumerated().map { index, song in
                        self?.makeTrackItem(song, tracks: songs, startIndex: index)
                    }.compactMap { $0 }
                    template?.updateSections([
                        CPListSection(items: items, header: "\(songs.count) 首", sectionIndexTitle: nil)
                    ])
                }
            } catch {
                await MainActor.run {
                    template?.updateSections([
                        CPListSection(items: [
                            CPListItem(text: "排行榜加载失败", detailText: "请稍后重试")
                        ])
                    ])
                }
            }
        }
    }

    private func showNowPlaying() {
        guard let interfaceController, player?.currentSong != nil else { return }
        let template = CPNowPlayingTemplate.shared
        template.isUpNextButtonEnabled = false
        template.isAlbumArtistButtonEnabled = false
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func setArtwork(for item: CPListItem, url: URL?) {
        guard let url else { return }
        Task { @MainActor in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            item.setImage(image)
        }
    }

}
