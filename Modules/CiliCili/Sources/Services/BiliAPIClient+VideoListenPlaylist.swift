import Foundation

extension BiliAPIClient {
    func fetchOfficialVideoListenPlaylist(
        aid: Int,
        cid: Int?,
        cursor: String? = nil,
        sortOrder: VideoListenPlaylistSortOrder = .normal
    ) async throws -> BiliListenerPlaylistPage {
        guard aid > 0 else { throw BiliListenerPlaylistError.invalidAnchor }
        let normalizedCursor = cursor?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if normalizedCursor?.isEmpty != false, (cid ?? 0) <= 0 {
            throw BiliListenerPlaylistError.invalidAnchor
        }

        let context = await videoListenPlaylistRequestContext()
        guard !context.guestModeEnabled,
            let accessKey = context.appAccessKey?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            !accessKey.isEmpty
        else {
            throw BiliListenerPlaylistError.missingAccessKey
        }

        let profile = BiliAppSigner.Profile.androidHD
        let buvid =
            Self.cookieValue(named: "buvid3", in: context.cookieHeader)
            ?? Self.cookieValue(named: "buvid4", in: context.cookieHeader)
            ?? Self.cookieValue(named: "buvid3", in: context.anonymousCookieHeader)
            ?? Self.cookieValue(named: "buvid4", in: context.anonymousCookieHeader)
            ?? ""
        let headers = BiliListenerPlaylistCodec.grpcHeaders(
            accessKey: accessKey,
            buvid: buvid,
            networkClass: PlaybackEnvironment.current.networkClass,
            traceID: Self.piliPlusTraceID()
        )
        let message = try BiliListenerPlaylistCodec.encodeRequest(
            aid: aid,
            cid: cid,
            cursor: normalizedCursor,
            sortOrder: sortOrder
        )
        var request = try await makeRequest(
            base: appURL,
            path: BiliListenerPlaylistCodec.endpointPath,
            query: [:],
            referer: "https://www.bilibili.com/video/av\(aid)",
            userAgent: profile.userAgent,
            cookieHeader: context.cookieHeader,
            additionalHeaders: headers,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = "POST"
        request.httpBody = BiliListenerPlaylistCodec.frame(message)

        let (data, response) = try await self.data(
            for: request,
            priority: URLSessionTask.highPriority,
            retryPolicy: .api
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BiliListenerPlaylistError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BiliListenerPlaylistError.invalidHTTPStatus(httpResponse.statusCode)
        }

        let biliStatus = httpResponse.value(forHTTPHeaderField: "bili-status-code")
            .flatMap { Int($0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)) }
        if let biliStatus, biliStatus != 0 {
            let message =
                httpResponse.value(forHTTPHeaderField: "bili-status-message")
                ?? httpResponse.value(forHTTPHeaderField: "grpc-message")
            throw BiliListenerPlaylistError.grpcStatus(
                biliStatus,
                message?.removingPercentEncoding ?? message
            )
        }

        let grpcStatus = httpResponse.value(forHTTPHeaderField: "grpc-status")
            .flatMap { Int($0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)) }
        if let grpcStatus, grpcStatus != 0 {
            let message = httpResponse.value(forHTTPHeaderField: "grpc-message")
            throw BiliListenerPlaylistError.grpcStatus(
                grpcStatus,
                message?.removingPercentEncoding ?? message
            )
        }

        guard !data.isEmpty else { throw BiliListenerPlaylistError.invalidResponse }
        let responseMessage = try BiliListenerPlaylistCodec.unframe(data)
        return try BiliListenerPlaylistCodec.decodeResponse(responseMessage)
    }
}
