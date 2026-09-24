// Beans host adapter for CiliCili (Rone89 and contributors), GPL-3.0-only.
import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
public final class CiliCiliRuntime: ObservableObject {
    public static let shared = CiliCiliRuntime()
    let dependencies = AppDependencies()
    @Published public private(set) var isDetailActive = false
    @Published public private(set) var integrationError: String?
    public var onPlaybackActivation: (() -> Void)?
    public var onSessionChange: ((String, String, String, String?) throws -> Void)?
    private var navigationOwners: Set<UUID> = []
    private var subscriptions = Set<AnyCancellable>()
    private var lastExportedIdentity = ""

    private init() {
        let session = dependencies.sessionStore
        Publishers.CombineLatest(session.$playbackCredentialVersion, session.$user)
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    // @Published emits before mutation. Export the committed snapshot.
                    await Task.yield()
                    self?.exportSessionIfChanged()
                }
            }
            .store(in: &subscriptions)
    }

    func setNavigationActive(_ active: Bool, owner: UUID) {
        if active { navigationOwners.insert(owner) } else { navigationOwners.remove(owner) }
        let value = !navigationOwners.isEmpty
        if isDetailActive != value { isDetailActive = value }
    }

    public func stopPlaybackForMusic() {
        ActivePlaybackCoordinator.shared.stopActivePlayback()
    }

    public var ownsPlayback: Bool { ActivePlaybackCoordinator.shared.currentActivePlayer() != nil }

    public func pauseForBackground() {
        ActivePlaybackCoordinator.shared.pauseActivePlaybackForAppBackground()
    }

    public var supportedOrientations: UIInterfaceOrientationMask {
        isDetailActive ? AppOrientationLock.supportedOrientations : .allButUpsideDown
    }

    public func synchronizeLegacySession(cookie: String, name: String, userID: String, avatar: String?) {
        let session = dependencies.sessionStore
        let values = Self.cookieValues(cookie)
        guard Self.credentialIdentity(values) != Self.credentialIdentity(Self.cookieValues(session.cookieHeader())) else {
            return
        }
        do {
            if values["SESSDATA"]?.isEmpty != false {
                if session.isLoggedIn { try session.logout() }
            } else {
                try session.saveLoginCookies(values, credentialKind: .web)
                session.updateUser(NavUserInfo(
                    isLogin: true, face: avatar, uname: name,
                    mid: Int(userID), wbiImg: nil
                ))
            }
            lastExportedIdentity = exportIdentity
            integrationError = nil
        } catch {
            integrationError = "哔哩哔哩账号同步失败：\(error.localizedDescription)"
        }
    }

    public func retrySessionExport() { exportSessionIfChanged() }

    private var exportIdentity: String {
        let session = dependencies.sessionStore
        return Self.credentialIdentity(Self.cookieValues(session.cookieHeader()))
            + "|" + (session.user?.uname ?? "") + "|" + (session.user?.face ?? "")
    }

    private func exportSessionIfChanged() {
        guard let onSessionChange, exportIdentity != lastExportedIdentity else { return }
        let session = dependencies.sessionStore
        do {
            try onSessionChange(
                session.isLoggedIn ? session.cookieHeader() : "",
                session.user?.uname ?? "", session.mainAccountMID.map(String.init) ?? "",
                session.user?.face
            )
            lastExportedIdentity = exportIdentity
            integrationError = nil
        } catch {
            integrationError = "无法同步到 Beans 音乐账号：\(error.localizedDescription)"
        }
    }

    nonisolated static func cookieValues(_ header: String) -> [String: String] {
        header.split(separator: ";").reduce(into: [:]) { values, part in
            let pair = part.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if pair.count == 2 { values[pair[0]] = pair[1] }
        }
    }

    nonisolated static func credentialIdentity(_ values: [String: String]) -> String {
        ["SESSDATA", "DedeUserID", "bili_jct"].map { values[$0] ?? "" }.joined(separator: "|")
    }
}

public struct CiliCiliHomeView: View {
    private let platforms: [String]
    private let selectPlatform: (String) -> Void
    private let startsWithSearch: Bool

    public init(platforms: [String], startsWithSearch: Bool = false, selectPlatform: @escaping (String) -> Void) {
        self.platforms = platforms
        self.startsWithSearch = startsWithSearch
        self.selectPlatform = selectPlatform
    }

    public var body: some View {
        RootTabView(platformNames: platforms, onSelectPlatform: selectPlatform, initialTab: startsWithSearch ? .search : .home)
            .modifier(CiliCiliEnvironment())
    }
}

struct CiliCiliEnvironment: ViewModifier {
    @ObservedObject private var runtime = CiliCiliRuntime.shared

    func body(content: Content) -> some View {
        content
            .environmentObject(runtime.dependencies)
            .environmentObject(runtime.dependencies.sessionStore)
            .environmentObject(runtime.dependencies.libraryStore)
            .environmentObject(runtime.dependencies.homeRecommendDiagnosticsStore)
            .environment(\.appThemeTintColor, runtime.dependencies.libraryStore.appTintColor)
            .environment(\.showsVideoCoverDurationBadges, runtime.dependencies.libraryStore.showsVideoCoverDurationBadges)
            .safeAreaInset(edge: .top) {
                if let error = runtime.integrationError {
                    HStack {
                        Text(error).font(.footnote)
                        Button("重试") { runtime.retrySessionExport() }
                    }
                    .padding(10).background(.regularMaterial)
                }
            }
            .task { runtime.dependencies.scheduleStartupWorkIfNeeded() }
    }
}

// Only foreground/background and orientation are forwarded. CiliCili's
// standalone app delegate must not clear Beans' Now Playing or app appearance.
public final class CiliCiliHostAppDelegate: NSObject, UIApplicationDelegate {
    public func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        CiliCiliRuntime.shared.supportedOrientations
    }

    public func applicationDidEnterBackground(_ application: UIApplication) {
        CiliCiliRuntime.shared.pauseForBackground()
    }

    public func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication) {
        CiliCiliRuntime.shared.pauseForBackground()
    }
}
