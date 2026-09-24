import Foundation

extension BiliAPIClient {
    private func favoriteFolderSummaries(
        rid: Int? = nil,
        context: InteractionRequestContext
    ) async throws -> [FavoriteFolder] {
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        guard let userMID = context.currentUserMID, userMID > 0 else {
            throw BiliAPIError.missingPayload
        }
        var query = [
            "up_mid": String(userMID),
            "type": "2",
        ]
        if let rid {
            query["rid"] = String(rid)
        }
        let response: BiliResponse<FavoriteFolderListData> = try await get(
            base: baseURL,
            path: "/x/v3/fav/folder/created/list-all",
            query: query,
            cookieHeader: context.cookieHeader
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        return response.payload?.list ?? []
    }

    private func requireInteractionCSRFContext() async throws -> (
        csrf: String,
        context: InteractionRequestContext
    ) {
        let context = await interactionRequestContext()
        guard context.isLoggedIn else {
            throw BiliAPIError.missingSESSDATA
        }
        guard let csrf = context.csrfToken, !csrf.isEmpty else {
            throw BiliAPIError.missingCSRF
        }
        return (csrf, context)
    }

    func fetchVideoInteractionState(aid: Int, bvid: String?) async throws -> VideoInteractionState {
        let context = await interactionRequestContext()
        guard context.isLoggedIn || context.appAccessKey?.isEmpty == false else {
            throw BiliAPIError.missingSESSDATA
        }

        do {
            let relationState = try await fetchVideoArchiveRelationState(
                aid: aid,
                bvid: bvid,
                context: context
            )
            var state = relationState.interactionState
            state.isFollowing = false
            return state
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Older web endpoints are a reliable fallback for cookie-based accounts.
        }

        guard context.isLoggedIn else {
            throw BiliAPIError.missingSESSDATA
        }

        async let like: BiliResponse<Int> = get(
            base: baseURL,
            path: "/x/web-interface/archive/has/like",
            query: ["aid": String(aid)],
            cookieHeader: context.cookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: URLSessionTask.defaultPriority
        )
        async let coin: BiliResponse<VideoCoinState> = get(
            base: baseURL,
            path: "/x/web-interface/archive/coins",
            query: ["aid": String(aid)],
            cookieHeader: context.cookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: URLSessionTask.defaultPriority
        )
        async let favorite: BiliResponse<VideoFavoriteState> = get(
            base: baseURL,
            path: "/x/v2/fav/video/favoured",
            query: ["aid": String(aid)],
            cookieHeader: context.cookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: URLSessionTask.defaultPriority
        )

        let (likeResponse, coinResponse, favoriteResponse) = try await (like, coin, favorite)

        guard likeResponse.code == 0 else {
            throw BiliAPIError.api(code: likeResponse.code, message: likeResponse.displayMessage)
        }
        guard coinResponse.code == 0 else {
            throw BiliAPIError.api(code: coinResponse.code, message: coinResponse.displayMessage)
        }
        guard favoriteResponse.code == 0 else {
            throw BiliAPIError.api(code: favoriteResponse.code, message: favoriteResponse.displayMessage)
        }

        return VideoInteractionState(
            isLiked: (likeResponse.payload ?? 0) == 1,
            coinCount: coinResponse.payload?.multiply ?? 0,
            isFavorited: favoriteResponse.payload?.favoured ?? false,
            isFollowing: false
        )
    }

    private func fetchVideoArchiveRelationState(
        aid: Int,
        bvid: String?,
        context: InteractionRequestContext
    ) async throws -> VideoArchiveRelationState {
        var query = ["aid": String(aid)]
        if let bvid, !bvid.isEmpty {
            query["bvid"] = bvid
        }
        if !context.isLoggedIn,
            let accessKey = context.appAccessKey,
            !accessKey.isEmpty
        {
            query["access_key"] = accessKey
        }

        let response: BiliResponse<VideoArchiveRelationState> = try await get(
            base: baseURL,
            path: "/x/web-interface/archive/relation",
            query: query,
            cookieHeader: context.cookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: URLSessionTask.defaultPriority
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let state = response.payload else { throw BiliAPIError.missingPayload }
        return state
    }

    func toggleVideoLike(aid: Int, liked: Bool) async throws {
        let context = try await requireInteractionCSRFContext()
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/web-interface/archive/like",
            body: [
                "aid": String(aid),
                "like": liked ? "1" : "2",
                "csrf": context.csrf,
                "cross_domain": "true",
                "source": "web_normal",
                "ga": "1",
            ],
            cookieHeader: context.context.cookieHeader,
            retryPolicy: .idempotentMutation
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }

    func setDynamicLike(dynamicID: String, liked: Bool) async throws {
        let normalizedID = dynamicID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { throw BiliAPIError.missingPayload }
        let context = try await requireInteractionCSRFContext()
        var request = try await makeRequest(
            base: baseURL,
            path: "/x/dynamic/feed/dyn/thumb",
            query: ["csrf": context.csrf],
            referer: "https://t.bilibili.com/\(normalizedID)",
            cookieHeader: context.context.cookieHeader
        )
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "dyn_id_str": normalizedID,
            "up": liked ? 1 : 2,
        ])
        let (data, _) = try await data(
            for: request,
            priority: URLSessionTask.highPriority,
            retryPolicy: .idempotentMutation
        )
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        let response: BiliResponse<EmptyBiliPayload> = try await Self.decode(
            data,
            priority: URLSessionTask.highPriority
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }

    func addVideoCoin(aid: Int, multiply: Int = 1, selectLike: Bool = false) async throws {
        guard (1...2).contains(multiply) else {
            throw BiliAPIError.api(code: -1, message: "投币数量无效")
        }
        let context = try await requireInteractionCSRFContext()
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/web-interface/coin/add",
            body: [
                "aid": String(aid),
                "multiply": String(multiply),
                "select_like": selectLike ? "1" : "0",
                "csrf": context.csrf,
                "cross_domain": "true",
                "source": "web_normal",
                "ga": "1",
            ],
            cookieHeader: context.context.cookieHeader
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }

    func setVideoFavorite(aid: Int, favorited: Bool) async throws {
        let context = try await requireInteractionCSRFContext()
        let folderIDs = try await favoriteFolderIDs(for: aid, context: context.context)
        let targetIDs: [Int]
        if favorited {
            guard let folderID = folderIDs.first else { throw BiliAPIError.missingPayload }
            targetIDs = [folderID]
        } else {
            targetIDs = folderIDs
            guard !targetIDs.isEmpty else { throw BiliAPIError.missingPayload }
        }

        let addMediaIDs = favorited ? targetIDs.map(String.init).joined(separator: ",") : ""
        let delMediaIDs = favorited ? "" : targetIDs.map(String.init).joined(separator: ",")
        try await submitFavoriteMutation(
            aid: aid,
            addMediaIDs: addMediaIDs,
            delMediaIDs: delMediaIDs,
            csrf: context.csrf,
            cookieHeader: context.context.cookieHeader
        )
    }

    func fetchFavoriteFolders(for aid: Int? = nil) async throws -> [FavoriteFolder] {
        let context = await interactionRequestContext()
        return try await favoriteFolderSummaries(rid: aid, context: context)
            .filter { $0.id > 0 }
    }

    func setVideoFavorite(aid: Int, addFolderIDs: Set<Int>, removeFolderIDs: Set<Int>) async throws {
        let context = try await requireInteractionCSRFContext()
        let addIDs =
            addFolderIDs
            .filter { $0 > 0 && !removeFolderIDs.contains($0) }
            .sorted()
        let removeIDs =
            removeFolderIDs
            .filter { $0 > 0 && !addFolderIDs.contains($0) }
            .sorted()
        guard !addIDs.isEmpty || !removeIDs.isEmpty else { return }

        try await submitFavoriteMutation(
            aid: aid,
            addMediaIDs: addIDs.map(String.init).joined(separator: ","),
            delMediaIDs: removeIDs.map(String.init).joined(separator: ","),
            csrf: context.csrf,
            cookieHeader: context.context.cookieHeader
        )
    }

    private func favoriteFolderIDs(for aid: Int, context: InteractionRequestContext) async throws -> [Int] {
        try await favoriteFolderSummaries(rid: aid, context: context)
            .filter { $0.id > 0 }
            .map(\.id)
    }

    private func submitFavoriteMutation(
        aid: Int,
        addMediaIDs: String,
        delMediaIDs: String,
        csrf: String,
        cookieHeader: String
    ) async throws {
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/v3/fav/resource/deal",
            body: [
                "rid": String(aid),
                "type": "2",
                "add_media_ids": addMediaIDs,
                "del_media_ids": delMediaIDs,
                "csrf": csrf,
                "platform": "web",
                "gaia_source": "web_normal",
                "ga": "1",
            ],
            cookieHeader: cookieHeader
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }

    func setUploaderFollowing(mid: Int, following: Bool) async throws {
        let context = await interactionRequestContext(purpose: .main)
        if let csrf = context.csrfToken, context.isLoggedIn {
            try await setUploaderFollowingWithWeb(mid: mid, following: following, csrf: csrf)
            return
        }
        if let accessKey = context.appAccessKey, !accessKey.isEmpty {
            try await setUploaderFollowingWithAppAccessKey(
                mid: mid,
                following: following,
                accessKey: accessKey,
                cookieHeader: context.cookieHeader
            )
            return
        }
        throw BiliAPIError.missingSESSDATA
    }

    private func setUploaderFollowingWithWeb(mid: Int, following: Bool, csrf: String) async throws {
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/relation/modify",
            body: [
                "fid": String(mid),
                "act": following ? "1" : "2",
                "re_src": "11",
                "csrf": csrf,
                "gaia_source": "web_normal",
                "ga": "1",
            ]
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }

    private func setUploaderFollowingWithAppAccessKey(
        mid: Int,
        following: Bool,
        accessKey: String,
        cookieHeader: String
    ) async throws {
        let profile = BiliAppSigner.Profile.androidLogin
        let response: BiliResponse<EmptyBiliPayload> = try await postSignedAPIForm(
            path: "/x/relation/modify",
            fields: [
                "access_key": accessKey,
                "fid": String(mid),
                "act": following ? "1" : "2",
                "re_src": "11",
                "gaia_source": "app_normal",
            ],
            profile: profile,
            cookieHeader: cookieHeader,
            additionalHeaders: Self.interactionAppHeaders(
                cookieHeader: cookieHeader,
                profile: profile
            )
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }
}
