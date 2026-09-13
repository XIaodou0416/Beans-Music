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
    private var homeTemplate: CPListTemplate?
    private var libraryTemplate: CPListTemplate?
    private var refreshScheduled = false

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
        let home = CPListTemplate(title: "主页", sections: [])
        home.tabImage = UIImage(systemName: "house")
        home.emptyViewTitleVariants = ["打开 Beans Music 开始播放"]

        let library = CPListTemplate(title: "音乐库", sections: [])
        library.tabImage = UIImage(systemName: "music.note.list")
        library.emptyViewTitleVariants = ["暂无播放记录"]

        homeTemplate = home
        libraryTemplate = library
        let root = CPTabBarTemplate(templates: [home, library])
        interfaceController.setRootTemplate(root, animated: true, completion: nil)
        scheduleRefresh()
    }

    func didDisconnect() {
        interfaceController = nil
        homeTemplate = nil
        libraryTemplate = nil
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refreshTemplates()
        }
    }

    private func refreshTemplates() {
        guard interfaceController != nil else { return }
        refreshHome()
        refreshLibrary()
    }

    private func refreshHome() {
        guard let homeTemplate else { return }
        guard let player else {
            homeTemplate.updateSections([])
            return
        }

        var sections: [CPListSection] = []
        if let currentSong = player.currentSong {
            let currentItem = CPListItem(text: currentSong.name, detailText: currentSong.artists)
            currentItem.accessoryType = .none
            currentItem.handler = { _, completion in completion() }
            setArtwork(for: currentItem, url: currentSong.coverURL)
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
        homeTemplate.updateSections(sections)
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

        libraryTemplate.updateSections(sections)
    }

    private func pushTrackList(title: String, tracks: [Song]) {
        guard let interfaceController, !tracks.isEmpty else { return }
        let template = CPListTemplate(title: title, sections: [])
        let items = tracks.enumerated().map { index, song in
            makeTrackItem(song, tracks: tracks, startIndex: index)
        }
        template.updateSections([CPListSection(items: items)])
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func makeTrackItem(_ song: Song, tracks: [Song], startIndex: Int) -> CPListItem {
        let item = CPListItem(text: song.name, detailText: song.artists)
        item.accessoryType = .none
        setArtwork(for: item, url: song.coverURL)
        item.handler = { [weak self] _, completion in
            self?.player?.play(songs: tracks, startAt: startIndex)
            completion()
        }
        return item
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
