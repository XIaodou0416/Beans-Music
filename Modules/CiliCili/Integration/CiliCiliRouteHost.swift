// Beans routes into CiliCili's original destination pages. GPL-3.0-only.
import SwiftUI

public enum CiliCiliRoute: Hashable {
    case video(bvid: String, title: String, cover: String?, cid: Int?)
    case uploader(mid: Int, name: String, avatar: String?)
    case live(roomID: Int)
    case collection(id: Int, isSeries: Bool, ownerID: Int, ownerName: String, title: String)
    case account
}

public struct CiliCiliRouteHost: View {
    private let initialRoute: CiliCiliRoute
    public init(route: CiliCiliRoute) { initialRoute = route }
    public var body: some View {
        CiliCiliRouteStack(initialRoute: initialRoute).modifier(CiliCiliEnvironment())
    }
}

private struct CiliCiliRouteStack: View {
    let initialRoute: CiliCiliRoute
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var path = NavigationPath()
    @State private var owner = UUID()
    @State private var browser: InAppBrowserItem?
    @StateObject private var mine = MineViewModelHolder()

    var body: some View {
        NavigationStack(path: $path) {
            initialPage
                .videoDestinations()
                .navigationDestination(for: MineOverlayRoute.self) { route in
                    RootMineNavigationDestination(
                        route: route, holder: mine, libraryStore: dependencies.libraryStore,
                        sessionStore: dependencies.sessionStore, api: dependencies.api
                    )
                }
                .dynamicDetailDestinations(path: $path, api: dependencies.api)
        }
        .environment(\.openVideoAction) { video in
            ActivePlaybackCoordinator.shared.pauseActivePlaybackForNavigation()
            path.append(video)
        }
        .environment(\.openVideoOwnerRouteAction) { path.append($0) }
        .environment(\.openPgcSeasonRouteAction) { path.append($0) }
        .environment(\.openLiveRoomAction) { room in
            ActivePlaybackCoordinator.shared.stopActivePlayback()
            path.append(room)
        }
        .environment(\.openAppURLAction, openAppURL)
        .environment(\.openURL, OpenURLAction { url in
            guard AppLinkRouter.canHandle(url) else { return .systemAction }
            openAppURL(url)
            return .handled
        })
        .sheet(item: $browser) { InAppBrowserView(url: $0.url).ignoresSafeArea() }
        .onAppear {
            CiliCiliRuntime.shared.setNavigationActive(true, owner: owner)
            if case .live = initialRoute { CiliCiliRuntime.shared.setLiveRoomActive(true, owner: owner) }
        }
        .onDisappear {
            CiliCiliRuntime.shared.setNavigationActive(false, owner: owner)
            CiliCiliRuntime.shared.setLiveRoomActive(false, owner: owner)
            ActivePlaybackCoordinator.shared.stopActivePlayback()
            AppOrientationLock.restorePortrait()
        }
        .task {
            mine.configure(api: dependencies.api, sessionStore: dependencies.sessionStore,
                           accountMessageService: dependencies.accountMessageService)
        }
    }

    @ViewBuilder private var initialPage: some View {
        switch initialRoute {
        case let .video(bvid, title, cover, cid):
            VideoDetailView(seedVideo: VideoItem(
                bvid: bvid, aid: nil, title: title, pic: cover, desc: nil,
                duration: nil, pubdate: nil, owner: nil, stat: nil, cid: cid,
                pages: nil, dimension: nil
            ), onRequestClose: { dismiss() })
        case let .uploader(mid, name, avatar):
            withCloseButton(UploaderView(owner: VideoOwner(mid: mid, name: name, face: avatar)))
        case let .live(roomID):
            LiveRoomDetailView(seedRoom: RootTabView.seedLiveRoom(roomID: roomID))
        case let .collection(id, isSeries, ownerID, ownerName, title):
            if let item = collectionItem(id: id, isSeries: isSeries, title: title) {
                withCloseButton(UploaderSeasonSeriesDetailView(
                    owner: VideoOwner(mid: ownerID, name: ownerName, face: nil), item: item
                ))
            } else {
                withCloseButton(ContentUnavailableView("合集信息无效", systemImage: "exclamationmark.triangle"))
            }
        case .account:
            withCloseButton(MineView(holder: mine) { path.append($0) })
        }
    }

    private func withCloseButton<Content: View>(_ content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关闭", systemImage: "xmark") { dismiss() }
            }
        }
    }

    private func collectionItem(id: Int, isSeries: Bool, title: String) -> UploaderSeasonSeriesItem? {
        let json: [String: Any] = ["meta": [isSeries ? "series_id" : "season_id": id, "name": title], "archives": []]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(UploaderSeasonSeriesItem.self, from: data)
    }

    private func openAppURL(_ url: URL) {
        Task { @MainActor in
            switch await AppLinkRouter.destination(for: url, api: dependencies.api) {
            case .video(let video): path.append(video)
            case .videoComment(let route): path.append(route)
            case .liveRoom(let room): path.append(room)
            case .user(let user): path.append(user)
            case .browser(let url): browser = InAppBrowserItem(url: url)
            }
        }
    }
}
