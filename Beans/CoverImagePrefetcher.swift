import Foundation

/// 在首帧之后后台预加载已知封面；只负责填充共享磁盘缓存，不修改任何 SwiftUI 状态。
@MainActor
final class CoverImagePrefetcher {
    static let shared = CoverImagePrefetcher()

    private var scheduledURLs = Set<URL>()
    private var didStartStartupPrefetch = false

    private init() {}

    func prefetchStartupCovers(
        auth: AuthStore,
        player: PlayerManager,
        favorites: FavoritesStore
    ) {
        guard !didStartStartupPrefetch else { return }
        didStartStartupPrefetch = true

        var urls = Set<URL>()
        for snapshot in DiscoverCache.shared.allSnapshots() {
            urls.formUnion(Self.urls(in: snapshot))
        }
        urls.formUnion(Self.urls(in: auth.playlists))
        urls.formUnion(Self.urls(in: player.queue))
        urls.formUnion(Self.urls(in: player.history))
        urls.formUnion(Self.urls(in: favorites.neteaseFavoriteSongs))
        urls.formUnion(Self.urls(in: favorites.qqFavoriteSongs))
        urls.formUnion(Self.urls(in: favorites.kugouFavoriteSongs))
        urls.formUnion(Self.urls(in: LocalLibraryStore.shared.playlists.flatMap(\.songs)))
        urls.formUnion(Self.urls(in: SyncedPlaylistCache.shared.allCachedPlaylists()))
        urls.formUnion(Self.urls(in: SyncedPlaylistCache.shared.allCachedSongs()))
        urls.formUnion(Self.urls(in: DetailSongsCache.shared.allCachedSongs()))
        schedule(urls)
    }

    /// 主页请求完成后立即补充本次新拿到的封面，不必等下次启动。
    func prefetch(snapshot: DiscoverCache.Snapshot) {
        schedule(Self.urls(in: snapshot))
    }

    private func schedule(_ urls: Set<URL>) {
        let pending = urls.subtracting(scheduledURLs)
        guard !pending.isEmpty else { return }
        scheduledURLs.formUnion(pending)
        Task.detached(priority: .utility) {
            await BeansCoverImageStore.prefetch(urls: pending)
        }
    }

    private static func urls(in snapshot: DiscoverCache.Snapshot) -> Set<URL> {
        var urls = Set<URL>()
        urls.formUnion(Self.urls(in: snapshot.dailySongs))
        urls.formUnion(snapshot.newAlbums.compactMap(\.coverURL))
        urls.formUnion(snapshot.topArtists.compactMap(\.coverURL))
        urls.formUnion(snapshot.topLists.compactMap(\.coverURL))
        urls.formUnion(Self.urls(in: snapshot.personalized))
        urls.formUnion(snapshot.qqTopLists.compactMap(\.coverURL))
        urls.formUnion(snapshot.kugouTopLists.compactMap(\.coverURL))
        return urls
    }

    private static func urls(in playlists: [Playlist]) -> Set<URL> {
        Set(playlists.flatMap { playlist in
            [playlist.coverURL, playlist.creatorAvatarURL].compactMap { $0 }
        })
    }

    private static func urls(in songs: [Song]) -> Set<URL> {
        Set(songs.compactMap(\.coverURL))
    }
}
