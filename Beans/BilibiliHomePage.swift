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
                        }
                        .refreshable {
                            if !submittedQuery.isEmpty && resultType != .song {
                                searchRefresh = UUID()
                            } else {
                                await feed.select(channel: channel, query: submittedQuery, force: true)
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
            .beansNavigationDestination(for: BilibiliNativeRoute.self) { route in
                BilibiliNativeDestination(route: route)
                    .environmentObject(navigation)
            }
        }
        .task {
            searchText = feed.query
            submittedQuery = feed.query
        }

        .onAppear {
            BeansDiagnostics.shared.route("哔哩哔哩主页")
            Task { await feed.select(channel: channel, query: submittedQuery, force: true) }
        }

        .onDisappear { searchTask?.cancel() }
        .fullScreenCover(item: $detailPresentation.presentedVideo) { presentedVideo in
            BeansDiagnostics.shared.route("哔哩哔哩视频详情")
            BilibiliNativeStandaloneStack(initialRoute: .video(presentedVideo))
                .environmentObject(player)
                .environmentObject(theme)
                .environment(\.bilibiliDismissVideo) { detailPresentation.dismiss() }
                .background(Color.black)
                .ignoresSafeArea()
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

