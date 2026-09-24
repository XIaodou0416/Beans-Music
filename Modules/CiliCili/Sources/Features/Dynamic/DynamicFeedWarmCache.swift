import Foundation

actor DynamicFeedWarmCache {
    static let shared = DynamicFeedWarmCache()

    private let freshnessInterval: TimeInterval = 90
    private var cachedPage: DynamicFeedData?
    private var cachedAt: Date?
    private var cachedIdentityKey: String?
    private var warmTask: Task<DynamicFeedData, Error>?
    private var warmTaskIdentityKey: String?
    private var warmTaskToken: UUID?

    func page(api: BiliAPIClient, identityKey: String) async throws -> DynamicFeedData {
        if let cachedPage = freshCachedPage(identityKey: identityKey) {
            return cachedPage
        }
        if let warmTask, warmTaskIdentityKey == identityKey {
            return try await warmTask.value
        }

        warmTask?.cancel()
        let token = UUID()
        let task = Task(priority: .utility) {
            try await api.fetchDynamicFeed()
        }
        warmTask = task
        warmTaskIdentityKey = identityKey
        warmTaskToken = token
        do {
            let page = try await task.value
            if warmTaskToken == token {
                store(page, identityKey: identityKey)
                clearWarmTask()
            }
            return page
        } catch {
            if warmTaskToken == token {
                clearWarmTask()
            }
            throw error
        }
    }

    func prewarm(api: BiliAPIClient, identityKey: String) async {
        guard freshCachedPage(identityKey: identityKey) == nil else { return }
        _ = try? await page(api: api, identityKey: identityKey)
    }

    func store(_ page: DynamicFeedData, identityKey: String) {
        cachedPage = page
        cachedAt = Date()
        cachedIdentityKey = identityKey
    }

    func clear() {
        warmTask?.cancel()
        clearWarmTask()
        cachedPage = nil
        cachedAt = nil
        cachedIdentityKey = nil
    }

    private func freshCachedPage(identityKey: String) -> DynamicFeedData? {
        guard let cachedPage,
              let cachedAt,
              cachedIdentityKey == identityKey,
              Date().timeIntervalSince(cachedAt) < freshnessInterval
        else { return nil }
        return cachedPage
    }

    private func clearWarmTask() {
        warmTask = nil
        warmTaskIdentityKey = nil
        warmTaskToken = nil
    }
}
