import SwiftUI

struct BilibiliHomePage: View {
    @ObservedObject private var platforms = PlatformPreferenceStore.shared
    @AppStorage("beans.homeSource") private var source = SearchProvider.bilibili.rawValue
    @State private var searchText = ""
    @State private var submittedQuery = ""
    @State private var resultType: SearchResultType = .all
    @State private var channel = BilibiliChannel.recommended
    @AppStorage(BilibiliExperience.key) private var mode = BilibiliExperience.listen.rawValue
    @StateObject private var navigation = BilibiliNavigationState()
    @State private var searchTask: Task<Void, Never>?
    @ObservedObject private var feed = BilibiliHomeFeedStore.shared

    var body: some View {
        BeansNavigationStackWithPath(path: $navigation.path) {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("播放模式", selection: $mode) {
                        ForEach(BilibiliExperience.allCases) { item in
                            Text(item.title).tag(item.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    channels
                    if channel != .live || !submittedQuery.isEmpty {
                        if !submittedQuery.isEmpty { Picker("搜索类型", selection: $resultType) { ForEach([SearchResultType.all, .song, .artist, .playlist]) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 8) }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) { if !submittedQuery.isEmpty && resultType != .all && resultType != .song { BilibiliSearchResults(keyword: submittedQuery, type: resultType) } else { BilibiliHomeFeed() } }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 190).beansAdaptiveContentWidth()
                        }.beansScrollIndicatorsHidden().beansScrollDismissesKeyboard()
                    } else { BilibiliLiveList() }
                }
            }
            .navigationTitle("哔哩哔哩").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索视频、UP主或合集")
            .onSubmit(of: .search) { submit() }
            .onChange(of: searchText) { value in
                searchTask?.cancel()
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { searchTask = Task { @MainActor in do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }; guard !Task.isCancelled else { return }; submit() } }
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !submittedQuery.isEmpty { submittedQuery = ""; if channel != .live { Task { await feed.select(channel: channel, query: "") } } }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Menu { ForEach(platforms.enabledSearchProviders.filter { $0 != .qishui }) { provider in Button(provider.rawValue) { source = provider.rawValue } } } label: { Image("BrandBilibili").resizable().scaledToFit().frame(width: 28, height: 28) }.accessibilityLabel("切换主页平台") }
                ToolbarItem(placement: .navigationBarTrailing) { BilibiliAccountShortcutButton { navigation.push(.account) } }
            }
            .beansHomeNavigationBarTransparent()
            .environmentObject(navigation)
            .environment(\.bilibiliNavigate, navigation.push)
            .beansNavigationDestination(for: BilibiliNativeRoute.self) { route in BilibiliNativeStandaloneStack(initialRoute: route).environmentObject(navigation) }
        }
        .task { searchText = feed.query; submittedQuery = feed.query; await feed.select(channel: channel, query: submittedQuery, force: true) }
        .onDisappear { searchTask?.cancel() }
        .tint(Color(red: 0.10, green: 0.43, blue: 0.86))
    }

    private var channels: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 20) { ForEach(BilibiliChannel.allCases) { item in Button { BeansHaptics.select(); channel = item; searchText = ""; submittedQuery = ""; if item != .live { Task { await feed.select(channel: item, query: "") } } } label: { VStack(spacing: 7) { Text(item.title).font(.subheadline.weight(channel == item ? .bold : .regular)); Capsule().fill(channel == item ? Color(red: 0.10, green: 0.43, blue: 0.86) : .clear).frame(height: 3) }.foregroundStyle(channel == item ? Color(red: 0.10, green: 0.43, blue: 0.86) : .secondary).frame(minHeight: 44) }.buttonStyle(.plain) } }.padding(.horizontal, 16) }
    }

    private func submit() { searchTask?.cancel(); submittedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines); Task { await feed.select(channel: channel == .live ? .recommended : channel, query: submittedQuery, force: true) } }
}
