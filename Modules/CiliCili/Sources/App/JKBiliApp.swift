import SwiftUI
import UIKit

@main
@MainActor
struct JKBiliApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 96 * 1024 * 1024,
            diskCapacity: 768 * 1024 * 1024
        )
        if UITestFixtureScenario.current != nil {
            UIView.setAnimationsEnabled(UITestFixtureScenario.animationsEnabled)
        }
        RefreshRateManager.shared.restorePersistedPreference()
    }

    var body: some Scene {
        WindowGroup {
            MainInterfaceHost()
                .background(LaunchWindowBackgroundInstaller())
        }
    }

}

private struct LaunchWindowBackgroundInstaller: UIViewRepresentable {
    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            LaunchAppearance.apply(to: view.window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        DispatchQueue.main.async {
            LaunchAppearance.apply(to: uiView.window)
        }
    }
}

private struct MainInterfaceHost: View {
    var body: some View {
        if let fixture = UITestFixtureScenario.current {
            if UITestFixtureScenario.animationsEnabled {
                UITestFixtureRootView(scenario: fixture)
            } else {
                UITestFixtureRootView(scenario: fixture)
                    .transaction { $0.disablesAnimations = true }
            }
        } else {
            ProductionMainInterfaceHost()
        }
    }
}

private struct ProductionMainInterfaceHost: View {
    @StateObject private var dependencies = AppDependencies()

    var body: some View {
        RootTabView()
            .scrollIndicators(.hidden, axes: .vertical)
            .environmentObject(dependencies)
            .environmentObject(dependencies.sessionStore)
            .environmentObject(dependencies.libraryStore)
            .environmentObject(dependencies.homeRecommendDiagnosticsStore)
            .background {
                AppFontSizePreferenceInstaller(libraryStore: dependencies.libraryStore)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
        }
    }
}

private struct AppFontSizePreferenceInstaller: UIViewRepresentable {
    @ObservedObject var libraryStore: LibraryStore

    func makeUIView(context _: Context) -> AppFontSizePreferenceView {
        let view = AppFontSizePreferenceView(frame: .zero)
        update(view)
        return view
    }

    func updateUIView(_ uiView: AppFontSizePreferenceView, context _: Context) {
        update(uiView)
    }

    private func update(_ view: AppFontSizePreferenceView) {
        view.apply(
            followsSystemFontSize: libraryStore.followsSystemFontSize,
            manualContentSizeCategory: libraryStore.manualFontSize.contentSizeCategory
        )
    }
}

private final class AppFontSizePreferenceView: UIView {
    private var followsSystemFontSize = true
    private var manualContentSizeCategory: UIContentSizeCategory = .large

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyToWindowScene()
    }

    func apply(
        followsSystemFontSize: Bool,
        manualContentSizeCategory: UIContentSizeCategory
    ) {
        self.followsSystemFontSize = followsSystemFontSize
        self.manualContentSizeCategory = manualContentSizeCategory
        applyToWindowScene()
    }

    private func applyToWindowScene() {
        guard let windowScene = window?.windowScene else { return }
        var overrides = windowScene.traitOverrides

        if followsSystemFontSize {
            guard overrides.contains(UITraitPreferredContentSizeCategory.self) else { return }
            overrides.remove(UITraitPreferredContentSizeCategory.self)
        } else {
            guard !overrides.contains(UITraitPreferredContentSizeCategory.self)
                    || windowScene.traitCollection.preferredContentSizeCategory != manualContentSizeCategory
            else { return }
            overrides.preferredContentSizeCategory = manualContentSizeCategory
        }

        windowScene.traitOverrides = overrides
    }
}
