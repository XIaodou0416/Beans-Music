import Foundation

nonisolated struct VideoContentRequestContext: Sendable {
    let cookieHeader: String
    let guestModeCookieHeader: String?
    let credentialVersion: Int
}

extension BiliAPIClient {
    func videoContentListTask(for key: String) async -> Task<[VideoItem], Error>? {
        await state.videoListTask(for: key)
    }

    func setVideoContentListTask(_ task: Task<[VideoItem], Error>, for key: String) async {
        await state.setVideoListTask(task, for: key)
    }

    func clearVideoContentListTask(for key: String) async {
        await state.clearVideoListTask(for: key)
    }

    func videoContentDetailTask(for key: String) async -> Task<VideoItem, Error>? {
        await state.videoDetailTask(for: key)
    }

    func setVideoContentDetailTask(_ task: Task<VideoItem, Error>, for key: String) async {
        await state.setVideoDetailTask(task, for: key)
    }

    func clearVideoContentDetailTask(for key: String) async {
        await state.clearVideoDetailTask(for: key)
    }

    func fetchPopularVideos(page: Int = 1) async throws -> [VideoItem] {
        let taskKey = "popular|\(page)"
        if let task = await videoContentListTask(for: taskKey) {
            return try await task.value
        }
        let task = Task<[VideoItem], Error>(priority: .userInitiated) { [self] in
            let response: BiliResponse<BiliPage<VideoItem>> = try await get(
                base: baseURL,
                path: "/x/web-interface/popular",
                query: [
                    "pn": String(page),
                    "ps": "20",
                ],
                responseCachePolicy: .brief
            )
            guard response.code == 0 else {
                throw BiliAPIError.api(code: response.code, message: response.displayMessage)
            }
            return response.payload?.list ?? []
        }
        await setVideoContentListTask(task, for: taskKey)
        do {
            let videos = try await task.value
            await clearVideoContentListTask(for: taskKey)
            return videos
        } catch {
            await clearVideoContentListTask(for: taskKey)
            throw error
        }
    }

    func fetchVideoDetail(bvid: String, bypassesCache: Bool = false) async throws -> VideoItem {
        let context = await videoContentRequestContext()
        if bypassesCache {
            let response: BiliResponse<VideoItem> = try await get(
                base: baseURL,
                path: "/x/web-interface/view",
                query: ["bvid": bvid],
                cookieHeader: context.cookieHeader,
                cachePolicy: .reloadIgnoringLocalCacheData,
                priority: URLSessionTask.highPriority
            )
            guard response.code == 0 else {
                throw BiliAPIError.api(code: response.code, message: response.displayMessage)
            }
            guard let item = response.payload else { throw BiliAPIError.missingPayload }
            return item
        }
        let taskKey = "bvid:\(bvid)|credential:\(context.credentialVersion)"
        if let task = await videoContentDetailTask(for: taskKey) {
            return try await task.value
        }
        let task = Task<VideoItem, Error>(priority: .userInitiated) { [self] in
            let response: BiliResponse<VideoItem> = try await get(
                base: baseURL,
                path: "/x/web-interface/view",
                query: ["bvid": bvid],
                cookieHeader: context.cookieHeader,
                responseCachePolicy: .detail
            )
            guard response.code == 0 else {
                throw BiliAPIError.api(code: response.code, message: response.displayMessage)
            }
            guard let item = response.payload else { throw BiliAPIError.missingPayload }
            return item
        }
        await setVideoContentDetailTask(task, for: taskKey)
        do {
            let item = try await task.value
            await clearVideoContentDetailTask(for: taskKey)
            return item
        } catch {
            await clearVideoContentDetailTask(for: taskKey)
            throw error
        }
    }

    func fetchVideoDetail(aid: Int) async throws -> VideoItem {
        let context = await videoContentRequestContext()
        let taskKey = "aid:\(aid)|credential:\(context.credentialVersion)"
        if let task = await videoContentDetailTask(for: taskKey) {
            return try await task.value
        }
        let task = Task<VideoItem, Error>(priority: .userInitiated) { [self] in
            let response: BiliResponse<VideoItem> = try await get(
                base: baseURL,
                path: "/x/web-interface/view",
                query: ["aid": String(aid)],
                cookieHeader: context.cookieHeader,
                responseCachePolicy: .detail
            )
            guard response.code == 0 else {
                throw BiliAPIError.api(code: response.code, message: response.displayMessage)
            }
            guard let item = response.payload else { throw BiliAPIError.missingPayload }
            return item
        }
        await setVideoContentDetailTask(task, for: taskKey)
        do {
            let item = try await task.value
            await clearVideoContentDetailTask(for: taskKey)
            return item
        } catch {
            await clearVideoContentDetailTask(for: taskKey)
            throw error
        }
    }

    func fetchVideoRelated(bvid: String) async throws -> [VideoItem] {
        let context = await videoContentRequestContext()
        let response: BiliResponse<[VideoItem]> = try await get(
            base: baseURL,
            path: "/x/web-interface/archive/related",
            query: [
                "bvid": bvid,
                "pn": "1",
                "ps": "40",
            ],
            userAgent: Self.webUserAgent,
            cookieHeader: context.guestModeCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData,
            responseCachePolicy: .short
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        return response.payload ?? []
    }

    func fetchVideoShot(bvid: String, cid: Int) async throws -> VideoShotMetadata {
        let normalizedBVID = bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBVID.isEmpty, cid > 0 else { throw BiliAPIError.missingPayload }
        let context = await playbackAPIRequestContext()
        let response: BiliResponse<VideoShotMetadata> = try await get(
            base: baseURL,
            path: "/x/player/videoshot",
            query: [
                "bvid": normalizedBVID,
                "cid": String(cid),
                "index": "1",
            ],
            referer: "https://www.bilibili.com/video/\(normalizedBVID)",
            userAgent: Self.webUserAgent,
            cookieHeader: context.cookieHeader,
            responseCachePolicy: .long,
            priority: URLSessionTask.defaultPriority
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let metadata = response.payload, metadata.isUsable else {
            throw BiliAPIError.missingPayload
        }
        return metadata
    }
}
