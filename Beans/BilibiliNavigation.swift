import SwiftUI

@MainActor
final class BilibiliPresentationState: ObservableObject {
    static let shared = BilibiliPresentationState()
    @Published private(set) var activeVideoIDs = Set<String>()

    func enterVideo(_ id: String) {
        activeVideoIDs.insert(id)
    }

    func leaveVideo(_ id: String) {
        activeVideoIDs.remove(id)
    }

    var isVideoDetailActive: Bool { !activeVideoIDs.isEmpty }
}

@MainActor
final class BilibiliDetailPresentation: ObservableObject {
    static let shared = BilibiliDetailPresentation()
    @Published var presentedVideo: Song?

    func present(_ song: Song) {
        BilibiliDetailDiagnostics.record("present request: \(song.identityKey)")
        presentedVideo = song
    }

    func dismiss() {
        BilibiliDetailDiagnostics.record("presenter dismiss")
        presentedVideo = nil
    }
}

@MainActor
final class BilibiliNavigationState: ObservableObject {
    @Published var path: [BilibiliNativeRoute] = []

    func push(_ route: BilibiliNativeRoute) {
        path.append(route)
    }

    func pop(to depth: Int) {
        guard path.count > depth else { return }
        path.removeLast(path.count - depth)
    }
}

private struct BilibiliNavigationActionKey: EnvironmentKey {
    static let defaultValue: ((BilibiliNativeRoute) -> Void)? = nil
}

private struct BilibiliDismissVideoKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var bilibiliNavigate: ((BilibiliNativeRoute) -> Void)? {
        get { self[BilibiliNavigationActionKey.self] }
        set { self[BilibiliNavigationActionKey.self] = newValue }
    }

    var bilibiliDismissVideo: (() -> Void)? {
        get { self[BilibiliDismissVideoKey.self] }
        set { self[BilibiliDismissVideoKey.self] = newValue }
    }
}

struct BilibiliNativeDestination: View {
    let route: BilibiliNativeRoute
    let legacyDepth: Int

    @ViewBuilder
    private var page: some View {
        switch route {
        case .video(let song): BilibiliVideoPage(song: song)
        case .up(let owner): BilibiliUPPage(owner: owner)
        case .collection(let collection): BilibiliCollectionPage(collection: collection)
        case .live(let room): BilibiliLivePage(room: room)
        case .playlist(let playlist): PlaylistView(playlist: playlist)
        case .account: BilibiliAccountPage()
        }
    }

    var body: some View {
        page
            .background { BilibiliLegacyRouteLink(depth: legacyDepth) }
    }
}

struct BilibiliNativeStandaloneStack: View {
    let initialRoute: BilibiliNativeRoute
    @StateObject private var navigation = BilibiliNavigationState()

    var body: some View {
        BeansNavigationStackWithPath(path: $navigation.path) {
            BilibiliNativeDestination(route: initialRoute, legacyDepth: 0)
                .environmentObject(navigation)
                .environment(\.bilibiliNavigate, navigation.push)
                .beansNavigationDestination(for: BilibiliNativeRoute.self) { route in
                    BilibiliNativeDestination(route: route, legacyDepth: 1)
                        .environmentObject(navigation)
                }
        }
    }
}

/// iOS 15 fallback: each visible level owns a hidden link into the same stack.
struct BilibiliLegacyRouteLink: View {
    let depth: Int
    @EnvironmentObject private var navigation: BilibiliNavigationState

    var body: some View {
        if #available(iOS 16, *) {
            EmptyView()
        } else {
            NavigationLink(
                destination: AnyView(destination),
                isActive: Binding(
                    get: { navigation.path.count > depth },
                    set: { if !$0 { navigation.pop(to: depth) } }
                )
            ) {
                EmptyView()
            }
            .frame(width: 0, height: 0)
            .hidden()
        }
    }

    @ViewBuilder
    private var destination: some View {
        if navigation.path.indices.contains(depth) {
            BilibiliNativeDestination(route: navigation.path[depth], legacyDepth: depth + 1)
                .environmentObject(navigation)
        } else {
            EmptyView()
        }
    }
}

struct BilibiliAccountShortcutButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var auth = BilibiliAuth.shared
    @AppStorage("beans.headerAccessoryMode") private var accessoryModeRaw = BeansHeaderAccessoryMode.avatar.rawValue
    let action: () -> Void

    var body: some View {
        Group {
            switch BeansHeaderAccessoryMode(rawValue: accessoryModeRaw) ?? .avatar {
            case .avatar:
                Button {
                    BeansHaptics.tap()
                    action()
                } label: {
                    avatar
                }
                .buttonStyle(.plain)
                .accessibilityLabel("哔哩哔哩账号与设置")
            case .themeToggle:
                BeansThemeToggleButton(colorScheme: colorScheme, usesGlassContainer: false)
            case .hidden:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if #available(iOS 26, *) {
            BeansAvatarView(remoteURL: auth.avatarURL, size: 38)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8) }
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        } else {
            BeansAvatarView(remoteURL: auth.avatarURL, size: 38)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8) }
                .padding(4)
                .background { BeansGlass(shape: Circle(), forceLiquid: true) }
                .clipShape(Circle())
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
    }
}

struct BilibiliAccountPage: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var navigation: BilibiliNavigationState
    @ObservedObject private var auth = BilibiliAuth.shared
    @State private var playlists: [Playlist] = []
    @State private var loadingPlaylists = false
    @State private var playlistsError: String?
    @State private var showingLogin = false
    @State private var showingWebLogin = false
    @State private var showingSMSLogin = false
    @State private var showingDetailLog = false

    var body: some View {
        List {
            Section("账号") {
                if auth.isLoggedIn {
                    HStack(spacing: 14) {
                        BeansAvatarView(remoteURL: auth.avatarURL, size: 62)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(auth.nickname.isEmpty ? "哔哩哔哩用户" : auth.nickname)
                                .font(BeansFont.appFont(17, .semibold))
                                .foregroundStyle(Color.beansLabel)
                            Text("UID \(auth.accountID)")
                                .font(BeansFont.appFont(12))
                                .foregroundStyle(Color.beansComment)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)

                    Button(role: .destructive) { auth.logout() } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("登录哔哩哔哩账号")
                            .font(BeansFont.appFont(16, .semibold))
                            .foregroundStyle(Color.beansLabel)
                        Text("登录后可收藏视频、关注 UP 主并查看个人收藏夹。")
                            .font(BeansFont.appFont(13))
                            .foregroundStyle(Color.beansComment)
                        HStack(spacing: 10) {
                            Button { showingLogin = true } label: {
                                Label("扫码登录", systemImage: "qrcode")
                                    .frame(maxWidth: .infinity, minHeight: 42)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.96, green: 0.31, blue: 0.50))

                            Button { showingWebLogin = true } label: {
                                Label("网页登录", systemImage: "safari")
                                    .frame(maxWidth: .infinity, minHeight: 42)
                            }
                            .buttonStyle(.bordered)
                        }
                        Button { showingSMSLogin = true } label: {
                            Label("手机号登录", systemImage: "iphone")
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 6)
                }
            }

            if auth.isLoggedIn {
                Section("账号内容") {
                    NavigationLink {
                        BilibiliAccountHistoryPage()
                    } label: {
                        Label("观看记录", systemImage: "clock.arrow.circlepath")
                    }

                    NavigationLink {
                        BilibiliPlaybackPreferencesPage()
                    } label: {
                        Label("播放设置", systemImage: "gearshape")
                    }

                    if loadingPlaylists && playlists.isEmpty {
                        ProgressView("正在加载收藏夹")
                    } else if let playlistsError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(playlistsError).font(.footnote).foregroundStyle(Color.beansComment)
                            Button("重新加载") { Task { await loadPlaylists() } }
                        }
                    } else if playlists.isEmpty {
                        Text("暂无可显示的收藏夹")
                            .foregroundStyle(Color.beansComment)
                    } else {
                        ForEach(playlists) { playlist in
                            Button { navigation.push(.playlist(playlist)) } label: {
                                HStack(spacing: 12) {
                                    CoverImage(url: playlist.coverURL, size: 44, cornerRadius: 7)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(playlist.name).font(BeansFont.appFont(14, .medium)).foregroundStyle(Color.beansLabel)
                                        Text("\(playlist.trackCount) 个视频").font(BeansFont.appFont(11)).foregroundStyle(Color.beansComment)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.beansComment)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("观看与播放") {
                BilibiliModeSettings()
            }

            Section("问题诊断") {
                Button {
                    showingDetailLog = true
                } label: {
                    Label("查看视频详情诊断日志", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .task { if auth.isLoggedIn { await loadPlaylists() } }
        .onReceive(NotificationCenter.default.publisher(for: .beansBilibiliLoginDidUpdate)) { _ in
            playlists = []
            playlistsError = nil
            if auth.isLoggedIn { Task { await loadPlaylists() } }
        }
        .sheet(isPresented: $showingLogin) {
            BilibiliLoginSheet().environmentObject(theme)
        }
        .sheet(isPresented: $showingWebLogin) {
            BilibiliWebLoginSheet()
        }
        .sheet(isPresented: $showingSMSLogin) {
            BilibiliSMSLoginSheet()
        }
        .sheet(isPresented: $showingDetailLog) {
            BilibiliDetailLogSheet()
        }
    }

    @MainActor
    private func loadPlaylists() async {
        guard auth.isLoggedIn, !loadingPlaylists else { return }
        loadingPlaylists = true
        playlistsError = nil
        defer { loadingPlaylists = false }
        do {
            playlists = try await BilibiliAPI.shared.personalPlaylists()
        } catch {
            playlistsError = error.localizedDescription
        }
    }
}

