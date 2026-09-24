import SwiftUI
import UIKit

struct PlaybackDetailPageLifecycleActions {
    private let onAppear: () -> Void
    private let onScenePhaseChanged: (ScenePhase) -> Void
    private let onDisappear: () -> Void

    init(
        onAppear: @escaping () -> Void = {},
        onScenePhaseChanged: @escaping (ScenePhase) -> Void = { _ in },
        onDisappear: @escaping () -> Void = {}
    ) {
        self.onAppear = onAppear
        self.onScenePhaseChanged = onScenePhaseChanged
        self.onDisappear = onDisappear
    }

    func handleAppear() {
        onAppear()
    }

    func handleScenePhaseChanged(_ phase: ScenePhase) {
        onScenePhaseChanged(phase)
    }

    func handleDisappear() {
        onDisappear()
    }
}

struct PlaybackDetailPageHost<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var hidesSystemChrome: Bool
    let background: Color
    let navigationBarVisibility: Visibility?
    let hidesBackButton: Bool
    let statusBarStyle: UIStatusBarStyle
    let performanceContext: PlaybackDetailPerformanceContext?
    let lifecycleActions: PlaybackDetailPageLifecycleActions
    let content: () -> Content

    init(
        hidesSystemChrome: Binding<Bool>,
        background: Color = Color(.systemGroupedBackground),
        navigationBarVisibility: Visibility? = nil,
        hidesBackButton: Bool = false,
        statusBarStyle: UIStatusBarStyle = .lightContent,
        performanceContext: PlaybackDetailPerformanceContext? = nil,
        lifecycleActions: PlaybackDetailPageLifecycleActions = PlaybackDetailPageLifecycleActions(),
        @ViewBuilder content: @escaping () -> Content
    ) {
        _hidesSystemChrome = hidesSystemChrome
        self.background = background
        self.navigationBarVisibility = navigationBarVisibility
        self.hidesBackButton = hidesBackButton
        self.statusBarStyle = statusBarStyle
        self.performanceContext = performanceContext
        self.lifecycleActions = lifecycleActions
        self.content = content
    }

    var body: some View {
        content()
            .playbackDetailViewChrome(
                navigationBarVisibility: navigationBarVisibility,
                hidesBackButton: hidesBackButton
            )
            .background(background)
            .onPreferenceChange(PlaybackDetailChromeHiddenPreferenceKey.self) { isHidden in
                hidesSystemChrome = isHidden
            }
            .playbackDetailSystemChrome(
                isHidden: hidesSystemChrome,
                statusBarStyle: statusBarStyle
            )
            .onAppear {
                if let performanceContext {
                    PlaybackDetailPerformanceMonitor.shared.begin(performanceContext)
                    PlaybackDetailPerformanceMonitor.shared.mark(.pageAppeared, context: performanceContext)
                }
                lifecycleActions.handleAppear()
            }
            .onChange(of: scenePhase) { _, phase in
                lifecycleActions.handleScenePhaseChanged(phase)
            }
            .onDisappear {
                lifecycleActions.handleDisappear()
                if let performanceContext {
                    PlaybackDetailPerformanceMonitor.shared.end(performanceContext)
                }
            }
    }
}
