import Foundation
import SwiftUI

struct BeansCacheItem: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable {
        case covers
        case homeAndPlaylists
        case details
        case lyrics
        case searchHistory

        var id: String { rawValue }
    }

    let category: Category
    let title: String
    let summary: String
    let bytes: Int64

    var id: String { category.id }
}

@MainActor
final class BeansCacheManager: ObservableObject {
    @Published private(set) var items: [BeansCacheItem] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isCleaning = false
    @Published var selectedIDs: Set<String> = []

    init() {}

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.bytes }
    }

    var selectedBytes: Int64 {
        items.reduce(0) { total, item in
            total + (selectedIDs.contains(item.id) ? item.bytes : 0)
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { [weak self] in
            let measured = await Self.measure()
            guard let self else { return }
            items = measured
            let validIDs = Set(measured.map(\.id))
            selectedIDs = selectedIDs.intersection(validIDs)
            isRefreshing = false
        }
    }

    func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func clearSelected() {
        let ids = selectedIDs
        guard !ids.isEmpty, !isCleaning else { return }

        isCleaning = true
        Task { [weak self] in
            guard let self else { return }
            if ids.contains(BeansCacheItem.Category.covers.id) {
                _ = await BeansCoverImageStore.clearCache()
            }
            clearNonCoverItems(ids)
            selectedIDs.removeAll()
            isCleaning = false
            refresh()
        }
    }

    static func formattedBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: bytes)
    }

    private func clearNonCoverItems(_ ids: Set<String>) {
        if ids.contains(BeansCacheItem.Category.homeAndPlaylists.id) {
            DiscoverCache.shared.clearAll()
            SyncedPlaylistCache.shared.clearAll()
        }
        if ids.contains(BeansCacheItem.Category.details.id) {
            ArtistHomeCache.shared.clearAll()
            RelatedAlbumsCache.shared.clearAll()
            DetailSongsCache.shared.clearAll()
        }
        if ids.contains(BeansCacheItem.Category.lyrics.id) {
            LyricsCache.shared.clearAll()
        }
        if ids.contains(BeansCacheItem.Category.searchHistory.id) {
            SearchHistoryStore.shared.clear()
        }
        BeansImageFileCache.removeAll()
    }

    private static func measure() async -> [BeansCacheItem] {
        let defaults = UserDefaults.standard
        let coverBytes = await BeansCoverImageStore.cacheSize()
        let homeBytes = dataSize(
            for: [
                "beans.discover.cache.v2",
                "beans.syncedPlaylistCache.playlists.v1",
                "beans.syncedPlaylistCache.songs.v1"
            ],
            defaults: defaults
        )
        let detailBytes = dataSize(
            for: [
                "beans.artistHomeCache.v1",
                "beans.relatedAlbumsCache.v1",
                "beans.detailSongsCache.v1"
            ],
            defaults: defaults
        )
        let lyricBytes = prefixedSize("beans.lyrics.cache.v1.", defaults: defaults)
        let historyBytes = dataSize(for: ["beans.search.history.v1"], defaults: defaults)

        return [
            BeansCacheItem(
                category: .covers,
                title: "封面缓存",
                summary: "歌曲、歌单、歌手和专辑封面",
                bytes: coverBytes
            ),
            BeansCacheItem(
                category: .homeAndPlaylists,
                title: "主页与歌单",
                summary: "主页推荐、歌单列表和已同步歌单",
                bytes: homeBytes
            ),
            BeansCacheItem(
                category: .details,
                title: "歌手与专辑详情",
                summary: "歌手主页、专辑和排行榜歌曲",
                bytes: detailBytes
            ),
            BeansCacheItem(
                category: .lyrics,
                title: "歌词缓存",
                summary: "最近播放过的歌词和逐字歌词数据",
                bytes: lyricBytes
            ),
            BeansCacheItem(
                category: .searchHistory,
                title: "搜索历史",
                summary: "搜索框中的历史关键词",
                bytes: historyBytes
            )
        ]
    }

    private static func dataSize(for keys: [String], defaults: UserDefaults) -> Int64 {
        keys.reduce(0) { total, key in
            guard let value = defaults.object(forKey: key) else { return total }
            return total + serializedSize(value)
        }
    }

    private static func prefixedSize(_ prefix: String, defaults: UserDefaults) -> Int64 {
        defaults.dictionaryRepresentation().reduce(Int64(0)) { total, pair in
            guard pair.key.hasPrefix(prefix) else { return total }
            return total + serializedSize(pair.value)
        }
    }

    private static func serializedSize(_ value: Any) -> Int64 {
        if let data = value as? Data {
            return Int64(data.count)
        }
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: value,
            format: .binary,
            options: 0
        ) else {
            return Int64(String(describing: value).utf8.count)
        }
        return Int64(data.count)
    }
}

struct CacheManagerView: View {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = BeansCacheManager()

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        summaryCard
                        cacheItemsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 120)
                    .beansAdaptiveContentWidth()
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle("缓存管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.beansAmber)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                clearFooter
            }
        }
        .task {
            manager.refresh()
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Beans 占用")
                        .font(BeansFont.appFont(21, .bold))
                        .foregroundStyle(Color.beansLabel)
                    Text("本地缓存、临时数据与可重新获取的内容")
                        .font(BeansFont.appFont(12))
                        .foregroundStyle(Color.beansComment)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(BeansCacheManager.formattedBytes(manager.totalBytes))
                    .font(BeansFont.appFont(22, .bold, .rounded))
                    .foregroundStyle(Color.beansLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            CacheUsageBar(items: manager.items, totalBytes: manager.totalBytes)
                .frame(height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text("已选择可释放")
                    .font(BeansFont.appFont(13, .medium))
                    .foregroundStyle(Color.beansComment)
                Text(BeansCacheManager.formattedBytes(manager.selectedBytes))
                    .font(BeansFont.appFont(20, .bold, .rounded))
                    .foregroundStyle(Color.beansLabel)
            }
        }
        .padding(20)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var cacheItemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("清理项目")
                    .font(BeansFont.appFont(21, .bold))
                    .foregroundStyle(Color.beansLabel)
                Text("按占用从大到小排列，可同时选择多个项目")
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
            }

            if manager.isRefreshing && manager.items.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(Color.beansAmber)
                    Text("正在计算缓存占用…")
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansComment)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background {
                    BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(manager.items.sorted { $0.bytes > $1.bytes }.enumerated()), id: \.element.id) { index, item in
                        cacheRow(item)
                        if index < manager.items.count - 1 {
                            Divider()
                                .overlay(Color.beansComment.opacity(0.16))
                                .padding(.leading, 76)
                        }
                    }
                }
                .background {
                    BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }

    private func cacheRow(_ item: BeansCacheItem) -> some View {
        let selected = manager.selectedIDs.contains(item.id)
        let color = color(for: item.category)
        return Button {
            BeansHaptics.select()
            manager.toggle(item.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(selected ? color : Color.beansComment.opacity(0.42), lineWidth: selected ? 0 : 2)
                        .frame(width: 28, height: 28)
                    if selected {
                        Circle()
                            .fill(color)
                            .frame(width: 28, height: 28)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                Image(systemName: icon(for: item.category))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(BeansFont.appFont(16, .semibold))
                        .foregroundStyle(Color.beansLabel)
                        .lineLimit(1)
                    Text(item.summary)
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                        .lineLimit(1)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(BeansCacheManager.formattedBytes(item.bytes))
                        .font(BeansFont.appFont(14, .semibold, .rounded))
                        .foregroundStyle(Color.beansLabel)
                        .lineLimit(1)
                    Text(percentageText(for: item))
                        .font(BeansFont.appFont(11, .medium, .rounded))
                        .foregroundStyle(Color.beansComment)
                }
                .frame(minWidth: 58, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.beansComment.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var clearFooter: some View {
        Button {
            BeansHaptics.medium()
            manager.clearSelected()
        } label: {
            HStack(spacing: 8) {
                if manager.isCleaning {
                    ProgressView().tint(.white)
                }
                Text(manager.isCleaning ? "正在清理…" : "清理已选 (BeansCacheManager.formattedBytes(manager.selectedBytes))")
                    .font(BeansFont.appFont(17, .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(manager.selectedBytes > 0 ? Color.beansSage : Color.beansComment.opacity(0.42))
            }
        }
        .buttonStyle(.plain)
        .disabled(manager.selectedBytes == 0 || manager.isCleaning)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func percentageText(for item: BeansCacheItem) -> String {
        guard manager.totalBytes > 0 else { return "0%" }
        let percentage = Double(item.bytes) / Double(manager.totalBytes) * 100
        return percentage < 0.1 ? "<0.1%" : String(format: "%.1f%%", percentage)
    }

    private func icon(for category: BeansCacheItem.Category) -> String {
        switch category {
        case .covers: return "photo.stack.fill"
        case .homeAndPlaylists: return "music.note.list"
        case .details: return "rectangle.stack.fill"
        case .lyrics: return "quote.bubble.fill"
        case .searchHistory: return "magnifyingglass"
        }
    }

    private func color(for category: BeansCacheItem.Category) -> Color {
        switch category {
        case .covers: return Color.beansAmber
        case .homeAndPlaylists: return Color.beansSage
        case .details: return Color.beansHighlight
        case .lyrics: return Color(red: 0.76, green: 0.38, blue: 0.52)
        case .searchHistory: return Color(red: 0.34, green: 0.53, blue: 0.86)
        }
    }
}

private struct CacheUsageBar: View {
    let items: [BeansCacheItem]
    let totalBytes: Int64

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(items) { item in
                    let ratio = totalBytes > 0 ? CGFloat(item.bytes) / CGFloat(totalBytes) : 0
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(color(for: item.category))
                        .frame(width: max(ratio > 0 ? proxy.size.width * ratio : 0, ratio > 0 ? 5 : 0))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.beansComment.opacity(0.12), in: Capsule())
            .clipShape(Capsule())
        }
    }

    private func color(for category: BeansCacheItem.Category) -> Color {
        switch category {
        case .covers: return Color.beansAmber
        case .homeAndPlaylists: return Color.beansSage
        case .details: return Color.beansHighlight
        case .lyrics: return Color(red: 0.76, green: 0.38, blue: 0.52)
        case .searchHistory: return Color(red: 0.34, green: 0.53, blue: 0.86)
        }
    }
}
