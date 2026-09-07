import SwiftUI

/// 独立的歌单广场页，主页中的歌单板块保持原样。
struct PlaylistSquareView: View {
    @EnvironmentObject private var theme: ThemeStore
    @ObservedObject private var platformPrefs = PlatformPreferenceStore.shared

    @AppStorage("beans.playlistSquareSource") private var playlistSourceRaw = SearchProvider.netease.rawValue
    @AppStorage("beans.uiStyle") private var uiStyleRaw = BeansUIStyle.liquid.rawValue
    @State private var playlists: [Playlist] = []
    @State private var selectedCategory = "全部"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var expanded = false

    private let categories = [
        "全部", "华语", "流行", "经典", "摇滚", "民谣", "电子", "影视原声", "ACG",
        "怀旧", "欧美", "日韩", "粤语", "古风", "轻音乐", "治愈", "学习", "运动", "夜晚"
    ]

    private var isNativeClean: Bool {
        BeansUIStyle(rawValue: uiStyleRaw) == .nativeClean
    }

    private var providers: [SearchProvider] {
        platformPrefs.enabledSearchProviders
    }

    private var source: SearchProvider {
        guard let saved = SearchProvider(rawValue: playlistSourceRaw), providers.contains(saved) else {
            return providers.first ?? .netease
        }
        return saved
    }

    private var visiblePlaylists: [Playlist] {
        expanded ? playlists : Array(playlists.prefix(18))
    }

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        sourcePicker

                        if source == .netease {
                            categoryChips
                        }

                        if isLoading && playlists.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 180)
                                .tint(Color.beansAmber)
                        } else if let errorMessage, playlists.isEmpty {
                            ErrorStateView(message: errorMessage) {
                                Task { await load(force: true) }
                            }
                            .frame(minHeight: 220)
                        } else if playlists.isEmpty {
                            EmptyStateView(icon: "music.note.list", text: emptyText)
                                .frame(maxWidth: .infinity, minHeight: 220)
                        } else {
                            playlistGrid
                            if playlists.count > 18 {
                                expandButton
                            }
                        }

                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, isNativeClean ? 20 : 16)
                    .padding(.top, 10)
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle(beansLocalized("歌单广场", "Playlist Square"))
            .navigationBarTitleDisplayMode(.inline)
            .task(id: "\(source.rawValue)-\(selectedCategory)") {
                await load(force: false)
            }
            .onReceive(platformPrefs.changes) { _ in
                if !providers.contains(source) {
                    playlistSourceRaw = (providers.first ?? .netease).rawValue
                    playlists = []
                }
            }
        }
    }

    private var sourcePicker: some View {
        HStack(spacing: 4) {
            ForEach(providers) { provider in
                Button {
                    BeansHaptics.tap()
                    guard source != provider else { return }
                    playlistSourceRaw = provider.rawValue
                    selectedCategory = "全部"
                    playlists = []
                    expanded = false
                } label: {
                    HStack(spacing: 5) {
                        if let imageName = provider.brandImageName {
                            Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                        Text(LocalizedStringKey(provider.rawValue))
                            .font(BeansFont.appFont(12, .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(source == provider ? Color.white : Color.beansComment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if source == provider { Capsule().fill(provider.tint) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            if isNativeClean { BeansSurface(shape: Capsule()) } else { BeansGlass(shape: Capsule()) }
        }
        .clipShape(Capsule())
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        guard selectedCategory != category else { return }
                        BeansHaptics.tap()
                        selectedCategory = category
                        playlists = []
                        expanded = false
                    } label: {
                        Text(LocalizedStringKey(category))
                            .font(BeansFont.appFont(12, .medium))
                            .foregroundStyle(selectedCategory == category ? Color.white : Color.beansComment)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background {
                                Capsule().fill(selectedCategory == category ? Color.beansAmber : Color.primary.opacity(0.06))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var playlistGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 14
        ) {
            ForEach(visiblePlaylists) { playlist in
                NavigationLink(destination: PlaylistView(playlist: playlist)) {
                    VStack(alignment: .leading, spacing: 8) {
                        CoverImage(url: playlist.coverURL, size: 150, cornerRadius: isNativeClean ? 14 : 18)
                            .frame(maxWidth: .infinity)
                        Text(playlist.name)
                            .font(BeansFont.appFont(13, .medium))
                            .foregroundStyle(Color.beansLabel)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(isNativeClean ? 0 : 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if !isNativeClean {
                            BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                }
                .buttonStyle(GlassPressButtonStyle(scale: 0.97))
            }
        }
    }

    private var expandButton: some View {
        Button {
            BeansHaptics.select()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(expanded
                     ? beansLocalized("收起歌单", "Collapse playlists")
                     : beansLocalized("展开全部（\(playlists.count)）", "Show all (\(playlists.count))"))
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
            }
            .font(BeansFont.appFont(13, .semibold))
            .foregroundStyle(Color.beansAmber)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background {
                if isNativeClean {
                    Capsule().fill(Color.primary.opacity(0.045))
                } else {
                    BeansGlass(shape: Capsule())
                }
            }
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.97))
    }

    private var emptyText: String {
        switch source {
        case .netease: return beansLocalized("推荐歌单暂时没有内容", "No NetEase playlists available")
        case .qq: return beansLocalized("QQ音乐热门歌单暂时没有内容", "No QQ Music playlists available")
        case .kugou: return beansLocalized("酷狗歌单广场暂时没有内容", "No Kugou playlists available")
        }
    }

    @MainActor
    private func load(force: Bool) async {
        if !force, !playlists.isEmpty { return }
        isLoading = true
        errorMessage = nil
        expanded = false
        do {
            switch source {
            case .netease:
                playlists = selectedCategory == "全部"
                    ? try await NetEaseAPI.shared.highQualityPlaylists(limit: 50)
                    : try await NetEaseAPI.shared.playlistSquare(cat: selectedCategory, order: "hot", limit: 50)
            case .qq:
                playlists = try await QQMusicAPI.shared.hotPlaylists(limit: 50)
            case .kugou:
                playlists = try await KugouMusicAPI.shared.recommendPlaylists(limit: 50)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
