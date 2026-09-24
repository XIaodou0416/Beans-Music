import Foundation

extension BiliAPIClient {
    func prewarmStartupResources() async {
        async let keys: Void = prewarmPlaybackSigningKeys()
        async let nav: NavUserInfo? = try? fetchNavUser()
        _ = await (keys, nav)
    }

    func resetPlaybackAuthorizationState() async {
        await state.clearAllPlayURLFailuresAndTasks()
        await ResourceCacheCenter.clearAPI()
    }

    func activeNavUserTask() async -> Task<NavUserInfo, Error>? {
        await state.navUserTask()
    }

    func storeNavUserTask(_ task: Task<NavUserInfo, Error>) async {
        await state.setNavUserTask(task)
    }

    func clearStoredNavUserTask() async {
        await state.clearNavUserTask()
    }
}
