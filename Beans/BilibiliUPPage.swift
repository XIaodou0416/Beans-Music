import SwiftUI

struct BilibiliUPPage: View {
    let owner: Artist
    @ObservedObject private var account = BilibiliAuth.shared
    @State private var profile: BilibiliUPProfile?
    @State private var videos: [BilibiliFeedVideo] = []
    @State private var collections: [BilibiliSeries] = []
    @State private var section = 0
    @State private var videoPage = 0
    @State private var seriesPage = 0
    @State private var videosMore = true
    @State private var seriesMore = true
    @State private var loading = false
    @State private var error: String?
    @State private var following: Bool?
    @State private var followingBusy = false
    @State private var showLogin = false
    @State private var route: BilibiliNativeRoute?
    @State private var message: String?
    private var creator: Artist { profile?.artist ?? owner }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                Picker("UP主内容", selection: $section) { Text("投稿").tag(0); Text("合集").tag(1) }
                    .pickerStyle(.segmented)
                if section == 0 {
                    BilibiliVideoRows(items: videos, onAppearItem: { id in
                        if id == videos.last?.id && videosMore && error == nil { Task { await loadMore() } }
                    })
                    if !loading && error == nil && videos.isEmpty { empty("暂无投稿") }
                } else {
                    ForEach(collections) { collection in
                        Button { route = .collection(collection) } label: { BilibiliCollectionRow(collection: collection) }
                            .buttonStyle(.plain)
                            .onAppear { if collection.id == collections.last?.id && seriesMore && error == nil { Task { await loadMore() } } }
                    }
                    if !loading && error == nil && collections.isEmpty { empty("暂无合集") }
                }
                if loading { ProgressView().frame(maxWidth: .infinity, minHeight: 50) }
                if let error { BilibiliInlineError(message: error) { Task { await loadMore() } } }
            }.padding(16).beansAdaptiveContentWidth()
        }
        .navigationTitle(creator.name).navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemBackground))
        .task {
            do { profile = try await BilibiliAPI.shared.upProfile(owner.id); following = profile?.following }
            catch { self.error = error.localizedDescription }
            await loadMore()
        }
        .onChange(of: section) { _ in
            error = nil
            if section == 0 ? videos.isEmpty : collections.isEmpty { Task { await loadMore() } }
        }
        .refreshable {
            if section == 0 { videoPage = 0; videosMore = true } else { seriesPage = 0; seriesMore = true }
            await loadMore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .beansBilibiliLoginDidUpdate)) { _ in
            Task { if let info = try? await BilibiliAPI.shared.upProfile(owner.id) { profile = info; following = info.following } }
        }
        .sheet(item: $route) { BilibiliNativeSheet(route: $0) }
        .sheet(isPresented: $showLogin) { BilibiliLoginSheet() }
        .alert("关注提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了") { message = nil }
        } message: { Text(message ?? "") }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                CoverImage(url: creator.coverURL, size: 68, cornerRadius: 34)
                VStack(alignment: .leading, spacing: 6) {
                    Text(creator.name).font(BeansFont.appFont(22, .bold)).foregroundStyle(Color.beansLabel)
                    if let profile { Text("\(BilibiliFeedVideo.countLabel(profile.followers)) 粉丝").font(.subheadline).foregroundStyle(Color.beansComment) }
                }
                Spacer(minLength: 4)
                Button(followingBusy ? "处理中" : following == true ? "已关注" : "+ 关注") { follow() }
                    .font(.subheadline).buttonStyle(.bordered).disabled(followingBusy)
            }
            if let sign = profile?.sign, !sign.isEmpty { Text(sign).font(.subheadline).foregroundStyle(Color.beansComment).textSelection(.enabled) }
        }.padding(16).background { BeansSurface(shape: RoundedRectangle(cornerRadius: 18)) }
    }
    private func empty(_ label: String) -> some View {
        Text(label).font(.subheadline).foregroundStyle(Color.beansComment).frame(maxWidth: .infinity, minHeight: 140)
    }
    private func follow() {
        guard account.isLoggedIn else { showLogin = true; return }
        guard !followingBusy else { return }
        followingBusy = true
        Task { @MainActor in
            defer { followingBusy = false }
            do {
                let value: Bool
                if let following { value = !following }
                else { value = !(try await BilibiliAPI.shared.upProfile(owner.id).following) }
                try await BilibiliAPI.shared.nativeFollow(id: owner.id, follow: value)
                following = value
            } catch { message = error.localizedDescription }
        }
    }
    @MainActor private func loadMore() async {
        guard !loading else { return }
        let requested = section
        guard requested == 0 ? videosMore : seriesMore else { return }
        loading = true; error = nil
        defer {
            loading = false
            if requested != section && (section == 0 ? videos.isEmpty : collections.isEmpty) { Task { await loadMore() } }
        }
        do {
            if requested == 0 {
                let next = videoPage + 1
                let result = try await BilibiliAPI.shared.upVideos(creator, page: next)
                try Task.checkCancellation()
                var seen = Set(next == 1 ? [] : videos.map(\.id))
                let addition = result.items.filter { seen.insert($0.id).inserted }
                videos = next == 1 ? addition : videos + addition
                videoPage = next; videosMore = result.more
            } else {
                let next = seriesPage + 1
                let result = try await BilibiliAPI.shared.upCollections(creator, page: next)
                try Task.checkCancellation()
                var seen = Set(next == 1 ? [] : collections.map(\.id))
                let addition = result.items.filter { seen.insert($0.id).inserted }
                collections = next == 1 ? addition : collections + addition
                seriesPage = next; seriesMore = result.more
            }
        } catch is CancellationError { }
        catch { if section == requested { self.error = error.localizedDescription } }
    }
}

struct BilibiliCollectionPage: View {
    let collection: BilibiliSeries
    @State private var items: [BilibiliFeedVideo] = []
    @State private var page = 0
    @State private var more = true
    @State private var loading = false
    @State private var error: String?
    @State private var route: BilibiliNativeRoute?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                BilibiliCollectionRow(collection: collection)
                if !collection.description.isEmpty { Text(collection.description).font(.subheadline).foregroundStyle(Color.beansComment) }
                Button {
                    route = .up(Artist(id: collection.ownerID, name: collection.ownerName, coverURL: nil, source: .bilibili))
                } label: { Label(collection.ownerName, systemImage: "person.crop.circle") }
                Divider()
                BilibiliVideoRows(items: items, onAppearItem: { id in
                    if id == items.last?.id && more && error == nil { Task { await load() } }
                })
                if loading { ProgressView().frame(maxWidth: .infinity, minHeight: 44) }
                if let error { BilibiliInlineError(message: error) { Task { await load() } } }
                if !loading && items.isEmpty && error == nil { Text("该合集暂无可见视频").foregroundStyle(.secondary) }
            }.padding(16).beansAdaptiveContentWidth()
        }
        .navigationTitle("合集").navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemBackground))
        .task { await load() }
        .refreshable { page = 0; more = true; await load() }
        .sheet(item: $route) { BilibiliNativeSheet(route: $0) }
    }
    @MainActor private func load() async {
        guard !loading, more else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let next = page + 1
            let result = try await BilibiliAPI.shared.seriesVideos(collection, page: next)
            try Task.checkCancellation()
            var seen = Set(next == 1 ? [] : items.map(\.id))
            let addition = result.items.filter { seen.insert($0.id).inserted }
            items = next == 1 ? addition : items + addition
            page = next; more = result.more
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}
