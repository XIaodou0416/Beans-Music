import Foundation

extension HomeViewModel {
    func refreshFromUserPull() async {
        let isModeSwitchRefresh = modeSwitchRefreshPending
        modeSwitchRefreshPending = false

        guard isModeSwitchRefresh || !isRefreshing else { return }
        if !isModeSwitchRefresh {
            let now = Date()
            if let lastUserRefreshDate,
               now.timeIntervalSince(lastUserRefreshDate) < 1.0 {
                return
            }
            lastUserRefreshDate = now
        }
        isUserRefreshing = true
        defer {
            isUserRefreshing = false
        }
        if isModeSwitchRefresh {
            await refresh(resetCursor: true)
        } else {
            await refresh(preservingExistingRecommendations: true)
        }
    }
}
