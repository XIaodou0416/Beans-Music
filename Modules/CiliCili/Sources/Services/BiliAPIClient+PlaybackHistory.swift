import Foundation
import OSLog

extension BiliAPIClient {
    private static let historyLogger = Logger(subsystem: "cc.bili", category: "History")

    func applyingConfiguredHistoryAccount(
        to data: PlayURLData,
        playbackUserMID: Int?
    ) async -> PlayURLData {
        let historySnapshot = requestSnapshot(purpose: .historyRead)
        guard historySnapshot.currentUserMID == playbackUserMID else {
            return data.removingHistoryMetadata()
        }
        return data
    }


    func reportVideoHistory(
        aid: Int?,
        cid: Int?,
        progress: TimeInterval,
        duration: TimeInterval?,
        bvid: String? = nil
    ) async throws {
        let context = await playbackHistoryRequestContext()
        guard context.isAccountPurposeEnabled else { return }
        var webError: Error?
        if let csrf = context.csrfToken, !csrf.isEmpty, context.isLoggedIn {
            do {
                try await reportVideoHeartbeatWithWeb(
                    aid: aid,
                    bvid: bvid,
                    cid: cid,
                    progress: progress,
                    csrf: csrf,
                    cookieHeader: context.cookieHeader
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                webError = error
                Self.historyLogger.error(
                    "historyReport webFailed fallback=history aid=\(aid ?? 0, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                if let aid, aid > 0 {
                    do {
                        try await reportVideoHistoryWithWeb(
                            aid: aid,
                            cid: cid,
                            progress: progress,
                            duration: duration,
                            csrf: csrf,
                            cookieHeader: context.cookieHeader
                        )
                        return
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        webError = error
                    }
                }
            }
        }

        if let aid, aid > 0, let accessKey = context.appAccessKey, !accessKey.isEmpty {
            do {
                try await reportVideoHistoryWithAppAccessKey(
                    aid: aid,
                    cid: cid,
                    progress: progress,
                    duration: duration,
                    accessKey: accessKey,
                    cookieHeader: context.cookieHeader
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.historyLogger.error(
                    "historyReport appFailed aid=\(aid, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                throw error
            }
        }

        if let webError {
            throw webError
        }
        throw BiliAPIError.missingSESSDATA
    }

    private func reportVideoHistoryWithWeb(
        aid: Int,
        cid: Int?,
        progress: TimeInterval,
        duration: TimeInterval?,
        csrf: String,
        cookieHeader: String
    ) async throws {
        var body = [
            "aid": String(aid),
            "progress": String(max(0, Int(progress))),
            "type": "3",
            "csrf": csrf,
            "gaia_source": "web_normal",
            "ga": "1",
        ]
        if let cid, cid > 0 {
            body["cid"] = String(cid)
        }
        if let duration, duration > 0 {
            body["duration"] = String(Int(duration))
        }
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/v2/history/report",
            body: body,
            userAgent: Self.webUserAgent,
            cookieHeader: cookieHeader
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }

    private func reportVideoHeartbeatWithWeb(
        aid: Int?,
        bvid: String?,
        cid: Int?,
        progress: TimeInterval,
        csrf: String,
        cookieHeader: String
    ) async throws {
        let normalizedBVID = bvid?.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = [
            "played_time": String(max(0, Int(progress))),
            "type": "3",
            "csrf": csrf,
        ]
        if let normalizedBVID, !normalizedBVID.isEmpty {
            body["bvid"] = normalizedBVID
        } else if let aid, aid > 0 {
            body["aid"] = String(aid)
        } else {
            throw BiliAPIError.missingPayload
        }
        if let cid, cid > 0 {
            body["cid"] = String(cid)
        }
        let referer: String
        if let normalizedBVID, !normalizedBVID.isEmpty {
            referer = "https://www.bilibili.com/video/\(normalizedBVID)"
        } else if let aid, aid > 0 {
            referer = "https://www.bilibili.com/video/av\(aid)"
        } else {
            referer = "https://www.bilibili.com"
        }
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: baseURL,
            path: "/x/click-interface/web/heartbeat",
            body: body,
            referer: referer,
            userAgent: Self.webUserAgent,
            cookieHeader: cookieHeader
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }

    private func reportVideoHistoryWithAppAccessKey(
        aid: Int,
        cid: Int?,
        progress: TimeInterval,
        duration: TimeInterval?,
        accessKey: String,
        cookieHeader: String
    ) async throws {
        let profile = BiliAppSigner.Profile.androidLogin
        let headerContext = Self.piliPodStyleAppRecommendHeaders(
            cookieHeader: cookieHeader,
            profile: profile
        )
        var fields = [
            "access_key": accessKey,
            "aid": String(aid),
            "progress": String(max(0, Int(progress))),
            "type": "3",
            "gaia_source": "app_normal",
        ]
        if let cid, cid > 0 {
            fields["cid"] = String(cid)
        }
        if let duration, duration > 0 {
            fields["duration"] = String(Int(duration))
        }
        let response: BiliResponse<EmptyBiliPayload> = try await postSignedAPIForm(
            path: "/x/v2/history/report",
            fields: fields,
            profile: profile,
            cookieHeader: cookieHeader,
            additionalHeaders: headerContext.headers
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }
}
