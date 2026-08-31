import SwiftUI
import UIKit

@main
struct BeansApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = AuthStore()
    @StateObject private var player = PlayerManager()
    @StateObject private var theme = ThemeStore.shared
    @StateObject private var favorites = FavoritesStore.shared
    /// 免责声明确认状态：未确认前主界面在模糊层下方可见，确认后移除门禁
    @AppStorage("beans.disclaimerAccepted") private var disclaimerAccepted = false

    init() {
        // 闪退检测：优先初始化，检测上次异常退出并安装崩溃捕获
        _ = CrashReporter.shared
        // 主页暂停只应在设置页打开期间生效，避免异常退出后把暂停状态永久写入本地。
        UserDefaults.standard.set(false, forKey: "beans.pauseHomeRendering")
        // 新安装默认开启高刷新率；老用户保留自己手动关闭的选择。
        HighRefreshKeeper.registerDefaults()
        HighRefreshKeeper.shared.configureFromDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(auth)
                    .environmentObject(player)
                    .environmentObject(theme)
                    .environmentObject(favorites)
                // 未确认前展示首次使用引导页（分页引导 + 免责确认）
                if !disclaimerAccepted {
                    OnboardingView { disclaimerAccepted = true }
                }
            }
            .task {
                // 先让系统完成首帧，再恢复仅影响已安装用户的数据与媒体偏好。
                await Task.yield()
                player.restorePersistedPlayMode()
                FontManager.reinstallIfNeeded()
                theme.restoreWallpapersIfNeeded()
                await RemoteControlStore.shared.refreshIfNeeded(force: true)
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active else { return }
                Task { await RemoteControlStore.shared.refreshIfNeeded() }
            }
        }
    }
}
