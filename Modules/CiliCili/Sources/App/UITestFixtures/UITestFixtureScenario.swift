import Foundation

/// Opt-in UI-test entry points. Production launches never select a fixture.
enum UITestFixtureScenario: String {
    case danmaku
    case dynamicDetail
    case fullscreen

    static var current: Self? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--ui-test-fixture") else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return Self(rawValue: arguments[valueIndex])
    }

    static var resetsPersistedState: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-reset-state")
    }

    static var animationsEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-enable-animations")
    }

    static var usesRootTabShell: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-root-tab-shell")
    }

    static var autoOpensDynamicDetail: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-auto-open-dynamic-detail")
    }

}
