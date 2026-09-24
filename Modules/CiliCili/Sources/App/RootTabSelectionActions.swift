import SwiftUI

extension RootTabView {
    var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                selectAvailableRootTab(tab)
            }
        )
    }

    func selectAvailableRootTab(_ tab: AppTab) {
        selectedTab = isAvailableRootTab(tab) ? tab : fallbackRootTab(for: tab)
    }

    var visibleRootTabs: [AppTab] {
        runtimeSettings.visibleRootTabs
    }

    func repairSelectedTabIfNeeded(visibleTabs: [AppTab]) {
        guard !visibleTabs.contains(selectedTab) else { return }
        selectedTab = fallbackRootTab(for: selectedTab, visibleTabs: visibleTabs)
    }

    func isAvailableRootTab(_ tab: AppTab) -> Bool {
        visibleRootTabs.contains(tab)
    }

    func fallbackRootTab(for tab: AppTab, visibleTabs: [AppTab]? = nil) -> AppTab {
        let tabs = visibleTabs ?? visibleRootTabs
        if tabs.contains(.home) { return .home }
        if tabs.contains(.mine) { return .mine }
        return tabs.first ?? .home
    }
}
