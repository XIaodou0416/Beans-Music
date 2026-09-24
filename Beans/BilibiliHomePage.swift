import SwiftUI
import UIKit

struct BilibiliHomePage: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerManager
    @ObservedObject private var platforms = PlatformPreferenceStore.shared
    @AppStorage("beans.homeSource") private var source = SearchProvider.bilibili.rawValue
    @AppStorage(BilibiliExperience.key) private var mode = BilibiliExperience.listen.rawValue
    @AppStorage("beans.homeWallpaperBlur") private var wallpaperBlur = 0.0
    @State private var searchText = ""
    @State private var submittedQuery = ""
    @State private var resultType: SearchResultType = .song
    @State private var channel = BilibiliChannel.recommended
    @StateObject private var navigation = BilibiliNavigationState()
    @State private var searchRefresh = UUID()
    @State private var searchTask: Task<Void, Never>?
    @ObservedObject private var detailPresentation = BilibiliDetailPresentation.shared
    @ObservedObject private var feed = BilibiliHomeFeedStore.shared

    var body: some View {
        BeansNavigationStackWithPath(path: $navigation.path) {
            ZStack {
                GlassBackdrop(customColor: theme.customBackground, homeMode: true, wallpaperBlur: CGFloat(wallpaperBlur))
                VStack(spacing: 0) {
                    channels
                    if channel != .live || !submittedQuery.isEmpty {
                        if !submittedQuery.isEmpty {
                            Picker("搜索类型", selection: $resultType) {
                                ForEach([SearchResultType.song, .artist, .playlist]) { item in
                                    Text(item.bilibiliTitle).tag(item)
                                }
                            }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 8)
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                if !submittedQuery.isEmpty && resultType != .song {
                                    BilibiliSearchResults(keyword: submittedQuery, type: resultType) { song in
                                        detailPresentation.present(song)
                                    }
                                        .id(searchRefresh)
                                } else {
                                    BilibiliHomeFeed { song in
                                        detailPresentation.present(song)
                                    }
                                }
                            }
                            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 190)
                            .beansAdaptiveContentWidth()
                            .background {
                                BilibiliPullRefresh {
                                    if !submittedQuery.isEmpty && resultType != .song { searchRefresh = UUID() }
                                    else { await feed.search(submittedQuery) }
                                }
                                    .frame(width: 0, height: 0)
                            }
                        }
                        .beansScrollIndicatorsHidden()
                        .beansScrollDismissesKeyboard()
                    } else {
                        BilibiliLiveList()
                    }
                }
            }
            .navigationTitle("哔哩哔哩")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索视频、UP主或合集")
            .onSubmit(of: .search) { submit() }
            .onChange(of: searchText) { value in
                searchTask?.cancel()
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchTask = Task { @MainActor in
                        do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
                        guard !Task.isCancelled else { return }
                        submit()
                    }
                }
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !submittedQuery.isEmpty {
                    submittedQuery = ""
                    if channel != .live { Task { await feed.select(channel: channel, query: "") } }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        ForEach(platforms.enabledSearchProviders.filter { $0 != .qishui }) { provider in
                            Button(provider.rawValue) { source = provider.rawValue }
                        }
                    } label: { Image("BrandBilibili").resizable().scaledToFit().frame(width: 28, height: 28) }
                    .accessibilityLabel("切换主页平台")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    BilibiliAccountShortcutButton { navigation.push(.account) }
                }
            }
            .beansHomeNavigationBarTransparent()
            .environmentObject(navigation)
            .environment(\.bilibiliNavigate, navigation.push)
            .background { BilibiliLegacyRouteLink(depth: 0) }
            .beansNavigationDestination(for: BilibiliNativeRoute.self) { route in
                BilibiliNativeDestination(route: route, legacyDepth: 1)
                    .environmentObject(navigation)
            }
        }
        .task {
            searchText = feed.query
            submittedQuery = feed.query
            // Refresh Bilibili content whenever the app surface appears.
            await feed.select(channel: channel, query: submittedQuery, force: true)
        }

        .onDisappear { searchTask?.cancel() }
        .overlay {
            if let presentedVideo = detailPresentation.presentedVideo {
                BilibiliNativeStandaloneStack(initialRoute: .video(presentedVideo))
                    .environmentObject(player)
                    .environmentObject(theme)
                    .environment(\.bilibiliDismissVideo) {
                        detailPresentation.dismiss()
                    }
                    .background(Color.black)
                    .ignoresSafeArea()
            } else {
                EmptyView()
            }
        }
        .onChange(of: detailPresentation.presentedVideo?.identityKey) { value in
            BilibiliDetailDiagnostics.record(value.map { "overlay state: \($0)" } ?? "overlay state: nil")
        }
    }

    private var channels: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(BilibiliChannel.allCases) { item in
                    Button {
                        BeansHaptics.select()
                        channel = item
                        searchText = ""
                        submittedQuery = ""
                        if item != .live { Task { await feed.select(channel: item, query: "") } }
                    } label: {
                        VStack(spacing: 7) {
                            Text(item.title).font(BeansFont.appFont(15, channel == item ? .bold : .regular))
                            Capsule().fill(channel == item ? Color.beansAmber : .clear).frame(height: 3)
                        }
                        .foregroundStyle(channel == item ? Color.beansAmber : Color.beansComment)
                        .frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 16)
        }
    }

    private func submit() {
        searchTask?.cancel()
        submittedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        searchRefresh = UUID()
        Task { await feed.select(channel: channel == .live ? .recommended : channel, query: submittedQuery, force: true) }
    }
}

/// UIRefreshControl works for UIScrollView on iOS 15 as well as newer systems.
private struct BilibiliPullRefresh: UIViewRepresentable {
    let refresh: () async -> Void
    func makeCoordinator() -> Coordinator { Coordinator(refresh: refresh) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.refresh = refresh
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.detach() }
    final class Coordinator: NSObject {
        var refresh: () async -> Void
        private weak var scroll: UIScrollView?
        private let control = UIRefreshControl()
        private var task: Task<Void, Never>?
        private var disposed = false
        init(refresh: @escaping () async -> Void) {
            self.refresh = refresh
            super.init()
            control.addTarget(self, action: #selector(pulled), for: .valueChanged)
        }
        func attach(from view: UIView) {
            guard !disposed else { return }
            var ancestor = view.superview
            while let next = ancestor {
                if let candidate = next as? UIScrollView {
                    if scroll !== candidate {
                        if scroll?.refreshControl === control { scroll?.refreshControl = nil }
                        scroll = candidate
                        candidate.refreshControl = control
                    }
                    return
                }
                ancestor = next.superview
            }
        }
        @objc private func pulled() {
            guard task == nil else { return }
            task = Task { @MainActor [weak self] in
                guard let self else { return }
                await refresh()
                control.endRefreshing()
                task = nil
            }
        }
        func detach() {
            disposed = true
            task?.cancel()
            if scroll?.refreshControl === control { scroll?.refreshControl = nil }
        }
    }
}

