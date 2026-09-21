import Foundation

/// Warms the first album/artist screens from data the user has already seen.
/// It never blocks the first frame and only prefetches existing cover URLs.
@MainActor
final class InitialCatalogWarmup {
    static let shared = InitialCatalogWarmup()

    private let completedKey = "beans.initialCatalogWarmup.v1"
    private var running = false

    private init() {}

    func runIfNeeded() async {
        guard !running, !UserDefaults.standard.bool(forKey: completedKey) else { return }
        running = true
        defer { running = false }

        var urls = Set<URL>()
        for snapshot in DiscoverCache.shared.allSnapshots() {
            urls.formUnion(snapshot.newAlbums.compactMap(\.coverURL))
            urls.formUnion(snapshot.topArtists.compactMap(\.coverURL))
            urls.formUnion(snapshot.dailySongs.compactMap(\.coverURL))
        }
        for entry in ArtistHomeCache.shared.allCachedEntries() {
            urls.formUnion(entry.albums.compactMap(\.coverURL))
            urls.formUnion(entry.songs.compactMap(\.coverURL))
            urls.formUnion([entry.artist?.coverURL].compactMap { $0 })
        }
        for entry in RelatedAlbumsCache.shared.allCachedEntries() {
            urls.formUnion(entry.albums.compactMap(\.coverURL))
        }

        // Keep launch-time work bounded; the remaining images still load on
        // demand when the user opens a detail page.
        let firstBatch = Set(Array(urls).prefix(48))
        guard !firstBatch.isEmpty else { return }
        await Task.yield()
        await BeansCoverImageStore.prefetch(urls: firstBatch)
        UserDefaults.standard.set(true, forKey: completedKey)
    }
}
