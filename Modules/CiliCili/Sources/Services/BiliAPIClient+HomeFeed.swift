import Foundation
import OSLog

extension BiliAPIClient {
    private static let appRecommendProfiles: [BiliAppSigner.Profile] = [.androidHD, .androidPhone]
    private static let primaryAppRecommendProfile: BiliAppSigner.Profile = .androidHD
    private static let recommendLogger = Logger(subsystem: "cc.bili", category: "HomeRecommend")
    private static let appRecommendHydrationCandidateLimit = 24
    private static let appRecommendHydrationConcurrencyLimit = 6

    func homeRecommendTask(for key: String) async -> Task<[VideoItem], Error>? {
        await state.videoListTask(for: key)
    }

    func setHomeRecommendTask(_ task: Task<[VideoItem], Error>, for key: String) async {
        await state.setVideoListTask(task, for: key)
    }

    func clearHomeRecommendTask(for key: String) async {
        await state.clearVideoListTask(for: key)
    }

    func clearHomeRecommendState() async {
        await state.clearHomeRecommendState()
    }

    func homeRecommendAppFeedIndex(defaulting defaultIndex: Int) async -> Int {
        await state.appRecommendFeedIndex(defaulting: defaultIndex)
    }

    func setHomeRecommendAppFeedIndex(_ index: Int?) async {
        await state.setAppRecommendFeedIndex(index)
    }

    func homeRecommendGuestModeCookieHeader() async -> String? {
        let context = await transportRequestContext()
        return context.guestModeEnabled ? context.anonymousCookieHeader : nil
    }

    func resetHomeRecommendState() async {
        await clearHomeRecommendState()
    }

    func fetchRecommendFeed(freshIndex: Int = 0, limit: Int? = nil) async throws -> [VideoItem] {
        let context = await homeRecommendRequestContext()
        let feedSource = context.feedSource
        let requestLimit = Self.normalizedRecommendLimit(limit)

        let taskKey = [
            "recommend",
            feedSource.rawValue,
            "idx-\(freshIndex)",
            "limit-\(requestLimit.map(String.init) ?? "default")",
            "guest-\(context.guestModeEnabled ? "1" : "0")",
            "identity-\(context.identityKey)",
            "accessKey-\(context.appAccessKey == nil ? "0" : "1")",
        ].joined(separator: "|")
        if let task = await homeRecommendTask(for: taskKey) {
            return try await task.value
        }
        let task = Task<[VideoItem], Error>(priority: .userInitiated) { [self] in
            switch feedSource {
            case .web:
                let videos = try await fetchWebRecommendFeed(
                    freshIndex: freshIndex,
                    limit: requestLimit
                )
                Self.recommendLogger.info(
                    "source=web endpoint=/x/web-interface/wbi/index/top/feed/rcmd freshIndex=\(freshIndex, privacy: .public) limit=\(requestLimit ?? 0, privacy: .public) count=\(videos.count, privacy: .public)"
                )
                return videos
            case .app:
                let fallbackContext: RecommendFallbackContext
                do {
                    let videos = try await fetchAppRecommendFeed(
                        freshIndex: freshIndex,
                        limit: requestLimit
                    )
                    if !videos.isEmpty {
                        Self.recommendLogger.info(
                            "source=app primaryProfile=\(Self.primaryAppRecommendProfile.displayName, privacy: .public) signed=1 endpoint=/x/v2/feed/index host=app.bilibili.com freshIndex=\(freshIndex, privacy: .public) limit=\(requestLimit ?? 0, privacy: .public) count=\(videos.count, privacy: .public)"
                        )
                        return videos
                    }
                    Self.recommendLogger.error(
                        "source=app fallback=web reason=empty primaryProfile=\(Self.primaryAppRecommendProfile.displayName, privacy: .public) freshIndex=\(freshIndex, privacy: .public)"
                    )
                    fallbackContext = RecommendFallbackContext(
                        fromSource: .app,
                        reason: "app-empty",
                        errorMessage: nil
                    )
                } catch {
                    Self.recommendLogger.error(
                        "source=app fallback=web reason=error primaryProfile=\(Self.primaryAppRecommendProfile.displayName, privacy: .public) freshIndex=\(freshIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                    )
                    fallbackContext = RecommendFallbackContext(
                        fromSource: .app,
                        reason: "app-error",
                        errorMessage: error.localizedDescription
                    )
                }
                let fallbackVideos = try await fetchWebRecommendFeed(
                    freshIndex: freshIndex,
                    limit: requestLimit,
                    fallbackContext: fallbackContext
                )
                Self.recommendLogger.info(
                    "source=web fallbackFrom=app endpoint=/x/web-interface/wbi/index/top/feed/rcmd freshIndex=\(freshIndex, privacy: .public) count=\(fallbackVideos.count, privacy: .public)"
                )
                return fallbackVideos
            }
        }
        await setHomeRecommendTask(task, for: taskKey)
        do {
            let videos = try await task.value
            await clearHomeRecommendTask(for: taskKey)
            return videos
        } catch {
            await clearHomeRecommendTask(for: taskKey)
            throw error
        }
    }

    private func fetchWebRecommendFeed(
        freshIndex: Int,
        limit: Int?,
        fallbackContext: RecommendFallbackContext? = nil
    ) async throws -> [VideoItem] {
        let context = await homeRecommendRequestContext()
        let cookieHeader = context.guestModeEnabled ? context.anonymousCookieHeader : context.cookieHeader
        let authDiagnostics = Self.recommendAuthDiagnostics(
            cookieHeader: cookieHeader,
            accessKey: nil,
            isLoggedIn: context.isLoggedIn,
            guestModeEnabled: context.guestModeEnabled
        )
        let keys = try await fetchWBIKeys(priority: URLSessionTask.highPriority)
        let pageSize = Self.recommendRequestPageSize(limit)
        let signed = WBISigner.sign(
            [
                "version": "1",
                "homepage_ver": "1",
                "feed_version": "V8",
                "ps": String(pageSize),
                "fresh_idx": String(freshIndex),
                "brush": String(freshIndex),
                "fresh_idx_1h": String(freshIndex),
                "fresh_type": "4",
            ], keys: keys)
        let diagnosticsRequestID = UUID()

        homeRecommendDiagnosticsStore.recordRequest(
            HomeRecommendDiagnosticsSnapshot(
                status: .requesting,
                source: .web,
                fallbackFromSource: fallbackContext?.fromSource,
                fallbackReason: fallbackContext?.reason,
                fallbackErrorMessage: fallbackContext?.errorMessage,
                fallbackAt: fallbackContext == nil ? nil : Date(),
                endpoint: "/x/web-interface/wbi/index/top/feed/rcmd",
                profile: "web-wbi",
                authMode: authDiagnostics.mode,
                isLoggedIn: authDiagnostics.isLoggedIn,
                guestModeEnabled: context.guestModeEnabled,
                hasAccessKey: false,
                hasSESSDATA: authDiagnostics.hasSESSDATA,
                hasDedeUserID: authDiagnostics.hasDedeUserID,
                hasBuvid: authDiagnostics.hasBuvid,
                hasBuvidFP: authDiagnostics.hasBuvidFP,
                identityKey: context.identityKey,
                requestedIndex: freshIndex,
                nextIndex: nil,
                nextIndexSource: nil,
                fingerprintSource: nil,
                sessionSource: nil,
                appKeyHeader: nil,
                signedAppKey: nil,
                appVersion: nil,
                build: nil,
                network: nil,
                requestProfile: nil,
                requestStartedAt: Date(),
                responseFinishedAt: nil,
                rawCount: nil,
                videoCardCount: nil,
                videoCount: nil,
                liveCardCount: nil,
                droppedCardCount: nil,
                recommendReasonCount: nil,
                errorMessage: nil,
                requestID: diagnosticsRequestID
            )
        )

        let response: BiliResponse<RecommendFeedData>
        do {
            response = try await get(
                base: baseURL,
                path: "/x/web-interface/wbi/index/top/feed/rcmd",
                query: signed,
                cookieHeader: await homeRecommendGuestModeCookieHeader(),
                cachePolicy: .reloadIgnoringLocalCacheData,
                responseCachePolicy: .brief
            )
        } catch {
            homeRecommendDiagnosticsStore.recordResponse(
                status: .failed,
                nextIndex: nil,
                nextIndexSource: nil,
                rawCount: nil,
                videoCardCount: nil,
                videoCount: nil,
                liveCardCount: nil,
                droppedCardCount: nil,
                recommendReasonCount: nil,
                errorMessage: error.localizedDescription,
                requestID: diagnosticsRequestID
            )
            throw error
        }
        guard response.code == 0 else {
            homeRecommendDiagnosticsStore.recordResponse(
                status: .failed,
                nextIndex: nil,
                nextIndexSource: nil,
                rawCount: nil,
                videoCardCount: nil,
                videoCount: nil,
                liveCardCount: nil,
                droppedCardCount: nil,
                recommendReasonCount: nil,
                errorMessage: response.displayMessage,
                requestID: diagnosticsRequestID
            )
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        let allVideos = response.payload?.feedItems.compactMap { $0.asVideoItem() } ?? []
        let videos = Self.limitedRecommendVideos(allVideos, limit: limit)
        homeRecommendDiagnosticsStore.recordResponse(
            status: .succeeded,
            nextIndex: nil,
            nextIndexSource: nil,
            rawCount: response.payload?.feedItems.count ?? 0,
            videoCardCount: response.payload?.feedItems.filter(\.isVideoCard).count ?? videos.count,
            videoCount: videos.count,
            liveCardCount: nil,
            droppedCardCount: max(0, (response.payload?.feedItems.count ?? allVideos.count) - allVideos.count),
            recommendReasonCount: videos.filter { $0.recommendReason?.isEmpty == false }.count,
            requestID: diagnosticsRequestID
        )
        return videos
    }

    private func fetchAppRecommendFeed(freshIndex: Int, limit: Int?) async throws -> [VideoItem] {
        let context = await homeRecommendRequestContext()
        let cookieHeader = context.guestModeEnabled ? context.anonymousCookieHeader : context.cookieHeader
        let accessKey = context.guestModeEnabled ? nil : context.appAccessKey
        let authDiagnostics = Self.recommendAuthDiagnostics(
            cookieHeader: cookieHeader,
            accessKey: accessKey,
            isLoggedIn: context.isLoggedIn,
            guestModeEnabled: context.guestModeEnabled
        )
        let requestedIndex: Int
        if freshIndex <= 0 {
            await setHomeRecommendAppFeedIndex(nil)
            requestedIndex = 0
        } else {
            requestedIndex = await homeRecommendAppFeedIndex(defaulting: freshIndex)
        }

        var lastError: Error?
        for (attemptIndex, profile) in Self.appRecommendProfiles.enumerated() {
            do {
                let videos = try await fetchAppRecommendFeed(
                    requestedIndex: requestedIndex,
                    cookieHeader: cookieHeader,
                    accessKey: accessKey,
                    limit: limit,
                    authDiagnostics: authDiagnostics,
                    context: context,
                    profile: profile,
                    fallbackProfile: attemptIndex == 0 ? nil : Self.appRecommendProfiles.first
                )
                if !videos.isEmpty || attemptIndex == Self.appRecommendProfiles.count - 1 {
                    return videos
                }
                Self.recommendLogger.error(
                    "source=app profileFallback reason=empty from=\(profile.displayName, privacy: .public) idx=\(requestedIndex, privacy: .public)"
                )
            } catch {
                lastError = error
                Self.recommendLogger.error(
                    "source=app profileFallback reason=error from=\(profile.displayName, privacy: .public) idx=\(requestedIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        throw lastError ?? BiliAPIError.missingPayload
    }

    private func fetchAppRecommendFeed(
        requestedIndex: Int,
        cookieHeader: String,
        accessKey: String?,
        limit: Int?,
        authDiagnostics: RecommendAuthDiagnostics,
        context: HomeRecommendRequestContext,
        profile: BiliAppSigner.Profile,
        fallbackProfile: BiliAppSigner.Profile?
    ) async throws -> [VideoItem] {
        let query = Self.piliPlusStyleAppRecommendQuery(
            freshIndex: requestedIndex,
            accessKey: accessKey,
            limit: limit,
            profile: profile
        )
        let headerContext = Self.piliPodStyleAppRecommendHeaders(
            cookieHeader: cookieHeader,
            profile: profile
        )
        let diagnosticsRequestID = UUID()
        homeRecommendDiagnosticsStore.recordRequest(
            HomeRecommendDiagnosticsSnapshot(
                status: .requesting,
                source: .app,
                endpoint: "/x/v2/feed/index",
                profile: profile.displayName,
                authMode: authDiagnostics.mode,
                isLoggedIn: authDiagnostics.isLoggedIn,
                guestModeEnabled: context.guestModeEnabled,
                hasAccessKey: authDiagnostics.hasAccessKey,
                hasSESSDATA: authDiagnostics.hasSESSDATA,
                hasDedeUserID: authDiagnostics.hasDedeUserID,
                hasBuvid: authDiagnostics.hasBuvid,
                hasBuvidFP: authDiagnostics.hasBuvidFP,
                identityKey: context.identityKey,
                requestedIndex: requestedIndex,
                nextIndex: nil,
                nextIndexSource: nil,
                fingerprintSource: headerContext.fingerprintSource,
                sessionSource: headerContext.sessionSource,
                appKeyHeader: headerContext.appKeyHeader,
                signedAppKey: profile.appKey,
                appVersion: profile.appVersion,
                build: profile.build,
                network: query["network"],
                requestProfile: Self.appRecommendRequestProfileSummary(
                    query: query,
                    headerContext: headerContext,
                    profile: profile,
                    fallbackProfile: fallbackProfile
                ),
                requestStartedAt: Date(),
                responseFinishedAt: nil,
                rawCount: nil,
                videoCardCount: nil,
                videoCount: nil,
                liveCardCount: nil,
                droppedCardCount: nil,
                recommendReasonCount: nil,
                errorMessage: nil,
                requestID: diagnosticsRequestID
            ))
        Self.recommendLogger.info(
            "source=app request endpoint=/x/v2/feed/index host=app.bilibili.com profile=\(profile.displayName, privacy: .public) signed=1 auth=\(authDiagnostics.mode, privacy: .public) loggedIn=\(authDiagnostics.isLoggedIn, privacy: .public) hasAccessKey=\(authDiagnostics.hasAccessKey, privacy: .public) hasSESSDATA=\(authDiagnostics.hasSESSDATA, privacy: .public) hasDedeUserID=\(authDiagnostics.hasDedeUserID, privacy: .public) hasBuvid=\(authDiagnostics.hasBuvid, privacy: .public) hasBuvidFP=\(authDiagnostics.hasBuvidFP, privacy: .public) idx=\(requestedIndex, privacy: .public) pull=\(requestedIndex == 0 ? "true" : "false", privacy: .public) fp=\(headerContext.fingerprintSource, privacy: .public) session=\(headerContext.sessionSource, privacy: .public) cacheIdentity=\(context.identityKey, privacy: .public) trace=per-request cache=snapshot-bypassed"
        )
        let response: BiliResponse<RecommendFeedData>
        do {
            response = try await get(
                base: appURL,
                path: "/x/v2/feed/index",
                query: BiliAppSigner.sign(query, profile: profile),
                referer: "https://www.bilibili.com",
                userAgent: profile.userAgent,
                cookieHeader: cookieHeader,
                additionalHeaders: headerContext.headers,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
        } catch {
            homeRecommendDiagnosticsStore.recordResponse(
                status: .failed,
                nextIndex: nil,
                nextIndexSource: nil,
                rawCount: nil,
                videoCardCount: nil,
                videoCount: nil,
                liveCardCount: nil,
                droppedCardCount: nil,
                recommendReasonCount: nil,
                errorMessage: error.localizedDescription,
                requestID: diagnosticsRequestID
            )
            throw error
        }
        guard response.code == 0 else {
            homeRecommendDiagnosticsStore.recordResponse(
                status: .failed,
                nextIndex: nil,
                nextIndexSource: nil,
                rawCount: nil,
                videoCardCount: nil,
                videoCount: nil,
                liveCardCount: nil,
                droppedCardCount: nil,
                recommendReasonCount: nil,
                errorMessage: response.displayMessage,
                requestID: diagnosticsRequestID
            )
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let payload = response.payload else {
            homeRecommendDiagnosticsStore.recordResponse(
                status: .succeeded,
                nextIndex: nil,
                nextIndexSource: nil,
                rawCount: 0,
                videoCardCount: 0,
                videoCount: 0,
                liveCardCount: 0,
                droppedCardCount: 0,
                recommendReasonCount: 0,
                requestID: diagnosticsRequestID
            )
            return []
        }
        let allVideos = payload.feedItems.compactMap { $0.asVideoItem() }
        let videos = Self.limitedRecommendVideos(allVideos, limit: limit)
        let nextIndexResult = payload.appNextIndexResult(after: requestedIndex)
        let nextIndex = nextIndexResult.value
        let videoCardCount = payload.feedItems.filter(\.isVideoCard).count
        let liveCardCount = payload.feedItems.filter {
            let kind = $0.resolvedCardKind
            return kind == "live" || kind == "live_room" || kind == "live_room_rcmd"
        }.count
        let droppedCardCount = max(0, payload.feedItems.count - videoCardCount)
        let recommendReasonCount = videos.filter { $0.recommendReason?.isEmpty == false }.count
        await setHomeRecommendAppFeedIndex(nextIndex)
        homeRecommendDiagnosticsStore.recordResponse(
            status: .succeeded,
            nextIndex: nextIndex,
            nextIndexSource: nextIndexResult.source,
            rawCount: payload.feedItems.count,
            videoCardCount: videoCardCount,
            videoCount: videos.count,
            liveCardCount: liveCardCount,
            droppedCardCount: droppedCardCount,
            recommendReasonCount: recommendReasonCount,
            requestID: diagnosticsRequestID
        )
        Self.recommendLogger.info(
            "source=app response endpoint=/x/v2/feed/index auth=\(authDiagnostics.mode, privacy: .public) profile=\(profile.displayName, privacy: .public) idx=\(requestedIndex, privacy: .public) nextIdx=\(nextIndex ?? -1, privacy: .public) nextIdxSource=\(nextIndexResult.source ?? "-", privacy: .public) rawCount=\(payload.feedItems.count, privacy: .public) videoCardCount=\(videoCardCount, privacy: .public) videoCount=\(videos.count, privacy: .public) liveCardCount=\(liveCardCount, privacy: .public) droppedCardCount=\(droppedCardCount, privacy: .public) recommendReasonCount=\(recommendReasonCount, privacy: .public)"
        )
        return videos
    }

    private static func piliPlusStyleAppRecommendQuery(
        freshIndex: Int,
        accessKey: String?,
        limit: Int?,
        profile: BiliAppSigner.Profile
    ) -> [String: String] {
        var query: [String: String]
        switch profile {
        case .androidHD:
            query = [
                "build": profile.build,
                "c_locale": "zh_CN",
                "channel": profile.channel,
                "column": "4",
                "device": profile.device,
                "device_name": "android",
                "device_type": "0",
                "disable_rcmd": "0",
                "flush": "5",
                "fnval": "976",
                "fnver": "0",
                "force_host": "2",
                "fourk": "1",
                "guidance": "0",
                "https_url_req": "0",
                "idx": String(freshIndex),
                "login_event": accessKey == nil ? "0" : "1",
                "mobi_app": profile.mobiApp,
                "network": "wifi",
                "platform": profile.platform,
                "player_net": "1",
                "pull": freshIndex == 0 ? "true" : "false",
                "qn": "32",
                "recsys_mode": "0",
                "s_locale": "zh_CN",
                "splash_id": "",
                "statistics": profile.statistics,
                "voice_balance": "0",
            ]
        case .androidPhone, .androidLogin, .androidTV:
            query = [
                "idx": String(freshIndex),
                "flush": "5",
                "pull": freshIndex == 0 ? "true" : "false",
                "device": profile.device,
                "login_event": accessKey == nil ? "0" : "1",
                "network": "wifi",
                "mobi_app": profile.mobiApp,
                "platform": profile.platform,
                "build": profile.build,
            ]
        }
        if let limit {
            let pageSize = String(recommendRequestPageSize(limit))
            query["ps"] = pageSize
            query["page_size"] = pageSize
        }
        if let accessKey {
            query["access_key"] = accessKey
        }
        return query
    }

    private static func normalizedRecommendLimit(_ limit: Int?) -> Int? {
        guard let limit else { return nil }
        return max(1, min(limit, 50))
    }

    private static func recommendRequestPageSize(_ limit: Int?) -> Int {
        normalizedRecommendLimit(limit) ?? 20
    }

    private static func limitedRecommendVideos(_ videos: [VideoItem], limit: Int?) -> [VideoItem] {
        guard let limit = normalizedRecommendLimit(limit), videos.count > limit else {
            return videos
        }
        return Array(videos.prefix(limit))
    }

    private struct RecommendFallbackContext {
        let fromSource: HomeRecommendFeedSourcePreference
        let reason: String
        let errorMessage: String?
    }

    private struct RecommendAuthDiagnostics {
        let mode: String
        let isLoggedIn: Bool
        let hasSESSDATA: Bool
        let hasAccessKey: Bool
        let hasDedeUserID: Bool
        let hasBuvid: Bool
        let hasBuvidFP: Bool
    }

    private static func appRecommendRequestProfileSummary(
        query: [String: String],
        headerContext: AppRecommendHeaderContext,
        profile: BiliAppSigner.Profile,
        fallbackProfile: BiliAppSigner.Profile?
    ) -> String {
        [
            "profile=\(profile.displayName)",
            "fallbackFrom=\(fallbackProfile?.displayName ?? "-")",
            "mobi_app=\(profile.mobiApp)",
            "platform=\(profile.platform)",
            "appver=\(profile.appVersion)",
            "build=\(profile.build)",
            "channel=\(profile.channel)",
            "device=\(query["device"] ?? "-")",
            "column=\(query["column"] ?? "-")",
            "disableRcmd=\(query["disable_rcmd"] ?? "-")",
            "network=\(query["network"] ?? "-")",
            "headerAppKey=\(headerContext.appKeyHeader)",
            "signedAppKey=\(profile.appKey)",
            "accessKey=\(query["access_key"] == nil ? "0" : "1")",
            "statistics=\(query["statistics"] == nil ? "0" : "1")",
        ].joined(separator: " ")
    }

    private static func recommendAuthDiagnostics(
        cookieHeader: String,
        accessKey: String?,
        isLoggedIn: Bool,
        guestModeEnabled: Bool
    ) -> RecommendAuthDiagnostics {
        let hasAccessKey = accessKey?.isEmpty == false
        let hasSESSDATA = cookieValue(named: "SESSDATA", in: cookieHeader) != nil
        let hasDedeUserID = cookieValue(named: "DedeUserID", in: cookieHeader) != nil
        let hasBuvid =
            cookieValue(named: "buvid3", in: cookieHeader) != nil
            || cookieValue(named: "buvid4", in: cookieHeader) != nil
        let hasBuvidFP =
            cookieValue(named: "buvid_fp", in: cookieHeader) != nil
            || cookieValue(named: "buvid_fp_plain", in: cookieHeader) != nil
        let mode: String
        if guestModeEnabled {
            mode = "guest"
        } else if hasAccessKey {
            mode = "app-access-key"
        } else if hasSESSDATA {
            mode = "cookie-only"
        } else {
            mode = "anon"
        }
        return RecommendAuthDiagnostics(
            mode: mode,
            isLoggedIn: isLoggedIn,
            hasSESSDATA: hasSESSDATA,
            hasAccessKey: hasAccessKey,
            hasDedeUserID: hasDedeUserID,
            hasBuvid: hasBuvid,
            hasBuvidFP: hasBuvidFP
        )
    }

    func hydrateRecommendMetadataIfNeeded(_ videos: [VideoItem]) async -> [VideoItem] {
        let hydrationCandidates = Array(
            videos.enumerated().filter { _, video in
                video.aid != nil && (video.pubdate == nil || video.owner?.face == nil)
            }.prefix(Self.appRecommendHydrationCandidateLimit))
        guard !hydrationCandidates.isEmpty else { return videos }

        let hydratedPairs = await withTaskGroup(of: (Int, VideoItem)?.self) { group in
            var nextCandidateIndex = 0
            let initialTaskCount = min(Self.appRecommendHydrationConcurrencyLimit, hydrationCandidates.count)

            for _ in 0..<initialTaskCount {
                let candidate = hydrationCandidates[nextCandidateIndex]
                nextCandidateIndex += 1
                group.addTask { [self] in
                    let (index, video) = candidate
                    guard let aid = video.aid else { return nil }
                    guard let fullDetail = try? await fetchVideoDetail(aid: aid) else { return nil }
                    return (index, video.mergingFilledValues(from: fullDetail))
                }
            }

            var pairs = [(Int, VideoItem)]()
            while let pair = await group.next() {
                if let pair {
                    pairs.append(pair)
                }
                if nextCandidateIndex < hydrationCandidates.count {
                    let candidate = hydrationCandidates[nextCandidateIndex]
                    nextCandidateIndex += 1
                    group.addTask { [self] in
                        let (index, video) = candidate
                        guard let aid = video.aid else { return nil }
                        guard let fullDetail = try? await fetchVideoDetail(aid: aid) else { return nil }
                        return (index, video.mergingFilledValues(from: fullDetail))
                    }
                }
            }
            return pairs
        }

        guard !hydratedPairs.isEmpty else { return videos }
        var mergedVideos = videos
        for (index, video) in hydratedPairs where mergedVideos.indices.contains(index) {
            mergedVideos[index] = video
        }
        return mergedVideos
    }
}
