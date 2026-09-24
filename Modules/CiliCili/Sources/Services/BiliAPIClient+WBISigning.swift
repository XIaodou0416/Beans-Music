import Foundation

extension BiliAPIClient {
    func clearWBIKeysForDynamicFeed() async {
        await state.clearWBIKeys()
    }

    func prewarmPlaybackSigningKeys() async {
        _ = try? await fetchWBIKeys(priority: URLSessionTask.defaultPriority)
    }

    func refreshPlaybackSigningKeys() async throws -> WBIKeys {
        await state.clearWBIKeys()
        return try await fetchWBIKeys(
            priority: URLSessionTask.highPriority,
            forcesNetworkRefresh: true
        )
    }

    func signedWBIQuery(_ query: [String: String]) async throws -> [String: String] {
        let keys = try await fetchWBIKeys(priority: URLSessionTask.highPriority)
        return WBISigner.sign(query, keys: keys)
    }

    func fetchWBIKeys(
        priority: Float = URLSessionTask.defaultPriority,
        forcesNetworkRefresh: Bool = false
    ) async throws -> WBIKeys {
        if !forcesNetworkRefresh, let keys = await freshCachedWBIKeys() {
            return keys
        }

        if !forcesNetworkRefresh, let task = await state.wbiKeysFetchTask() {
            return try await task.value
        }

        let task = Task<WBIKeys, Error>(priority: priority >= URLSessionTask.highPriority ? .userInitiated : .utility) {
            [self] in
            let response: BiliResponse<NavUserInfo> = try await get(
                base: baseURL,
                path: "/x/web-interface/nav",
                query: [:],
                cachePolicy: forcesNetworkRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy,
                priority: priority
            )
            guard let image = response.payload?.wbiImg else {
                if response.code != 0 {
                    throw BiliAPIError.api(code: response.code, message: response.displayMessage)
                }
                throw BiliAPIError.missingPayload
            }
            return WBIKeys(
                imgKey: Self.fileStem(from: image.imgURL),
                subKey: Self.fileStem(from: image.subURL)
            )
        }
        await state.setWBIKeysFetchTask(task)
        do {
            let keys = try await task.value
            await state.storeWBIKeys(keys)
            return keys
        } catch {
            await state.clearWBIKeysFetchTask()
            throw error
        }
    }

    private func freshCachedWBIKeys() async -> WBIKeys? {
        await state.freshCachedWBIKeys()
    }

    private static func fileStem(from url: String) -> String {
        let filename = URL(string: url)?.deletingPathExtension().lastPathComponent
        return filename ?? ""
    }
}
