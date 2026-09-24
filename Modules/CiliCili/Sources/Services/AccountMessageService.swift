import Foundation

@MainActor
final class AccountMessageService {
    private let apiBaseURL = URL(string: "https://api.bilibili.com")!
    private let messageBaseURL = URL(string: "https://message.bilibili.com")!
    private let privateMessageBaseURL = URL(string: "https://api.vc.bilibili.com")!
    private let sessionStore: SessionStore
    private let api: BiliAPIClient
    private let session: URLSession
    private let diagnostics: AccountMessageDiagnosticsStore

    init(
        sessionStore: SessionStore,
        api: BiliAPIClient,
        session: URLSession? = nil,
        diagnostics: AccountMessageDiagnosticsStore? = nil
    ) {
        self.sessionStore = sessionStore
        self.api = api
        self.session = session ?? Self.makeSession()
        self.diagnostics = diagnostics ?? .shared
    }

    func fetchUnreadSummary() async throws -> AccountMessageUnreadSummary {
        try await diagnosed(
            operation: "unread_summary",
            successDetails: { ["total": String($0.total)] }
        ) {
            try requireLoggedIn()
            let data = try await request(
                base: apiBaseURL,
                path: "/x/msgfeed/unread",
                query: [
                    "build": "0",
                    "mobi_app": "web",
                    "platform": "web"
                ]
            )
            return try AccountMessagePayloadDecoder.unreadSummary(from: data)
        }
    }

    func fetchAccountMessageInlineEmotes() async throws -> [String: BiliInlineEmote] {
        try await diagnosed(
            operation: "emote_panel",
            successDetails: { ["emotes": String($0.count)] }
        ) {
            try requireLoggedIn()
            let data = try await request(
                base: apiBaseURL,
                path: "/x/emote/user/panel/web",
                query: [
                    "business": "reply",
                    "web_location": "333.1245"
                ]
            )
            return try AccountMessagePayloadDecoder.accountMessageInlineEmotes(from: data)
        }
    }

    func fetchPrivateMessageUnreadCount() async throws -> Int {
        try await diagnosed(
            operation: "private_unread",
            successDetails: { ["count": String($0)] }
        ) {
            try requireLoggedIn()
            let query = try await api.signedWBIQuery([
                "session_type": "1",
                "group_fold": "1",
                "unfollow_fold": "0",
                "sort_rule": "2",
                "build": "0",
                "mobi_app": "web"
            ])
            let data = try await request(
                base: privateMessageBaseURL,
                path: "/session_svr/v1/session_svr/get_sessions",
                query: query,
                referer: "https://message.bilibili.com/"
            )
            return try AccountMessagePayloadDecoder.privateMessageUnreadCount(from: data)
        }
    }

    func fetchPage(
        category: AccountMessageCategory,
        cursor: AccountMessageCursor? = nil,
        pageSize: Int = 20
    ) async throws -> AccountMessagePage {
        try await diagnosed(
            operation: "feed_page",
            details: [
                "category": category.rawValue,
                "page": cursor == nil ? "first" : "next"
            ],
            successDetails: {
                ["items": String($0.items.count), "hasMore": String($0.hasMore)]
            }
        ) {
            try requireLoggedIn()

            switch category {
            case .reply:
                var query = standardFeedQuery()
                if let id = cursor?.id { query["id"] = String(id) }
                if let timestamp = cursor?.timestamp { query["reply_time"] = String(timestamp) }
                let data = try await request(base: apiBaseURL, path: "/x/msgfeed/reply", query: query)
                return try AccountMessagePayloadDecoder.page(category: category, from: data, pageSize: pageSize)

            case .mention:
                var query = standardFeedQuery()
                if let id = cursor?.id { query["id"] = String(id) }
                if let timestamp = cursor?.timestamp { query["at_time"] = String(timestamp) }
                let data = try await request(base: apiBaseURL, path: "/x/msgfeed/at", query: query)
                return try AccountMessagePayloadDecoder.page(category: category, from: data, pageSize: pageSize)

            case .like:
                var query = standardFeedQuery()
                if let id = cursor?.id { query["id"] = String(id) }
                if let timestamp = cursor?.timestamp { query["like_time"] = String(timestamp) }
                let data = try await request(base: apiBaseURL, path: "/x/msgfeed/like", query: query)
                return try AccountMessagePayloadDecoder.page(category: category, from: data, pageSize: pageSize)

            case .system:
                var query = [
                    "page_size": String(max(1, min(pageSize, 50))),
                    "mobi_app": "web",
                    "build": "0",
                    "web_location": "333.40164"
                ]
                if let cursorID = cursor?.id { query["cursor"] = String(cursorID) }
                let data = try await request(
                    base: messageBaseURL,
                    path: "/x/sys-msg/query_notify_list",
                    query: query,
                    referer: "https://message.bilibili.com"
                )
                let page = try AccountMessagePayloadDecoder.page(category: category, from: data, pageSize: pageSize)
                if cursor == nil,
                   let newestCursor = AccountMessagePayloadDecoder.newestSystemCursor(from: data) {
                    try? await updateSystemReadCursor(newestCursor)
                }
                return page
            }
        }
    }

    func fetchLikeDetail(cardID: Int, page: Int, lastMID: Int?) async throws -> AccountMessageLikeDetailPage {
        try requireLoggedIn()
        var query = standardFeedQuery()
        query["card_id"] = String(cardID)
        query["pn"] = String(max(1, page))
        if let lastMID, lastMID > 0 {
            query["last_mid"] = String(lastMID)
        }
        let data = try await request(base: apiBaseURL, path: "/x/msgfeed/like_detail", query: query)
        return try AccountMessagePayloadDecoder.likeDetail(from: data)
    }

    func fetchFollowers(page: Int, pageSize: Int = 20) async throws -> AccountMessageFollowerPage {
        try requireLoggedIn()
        guard let mid = currentUserMID() else {
            throw BiliAPIError.api(code: -1, message: "无法识别当前账号")
        }
        let size = max(1, min(pageSize, 50))
        let data = try await request(
            base: apiBaseURL,
            path: "/x/relation/fans",
            query: [
                "vmid": String(mid),
                "pn": String(max(1, page)),
                "ps": String(size),
                "order": "desc",
                "order_type": "attention"
            ]
        )
        return try AccountMessagePayloadDecoder.followers(
            from: data,
            page: max(1, page),
            pageSize: size
        )
    }

    func fetchPrivateMessageSessions() async throws -> [AccountPrivateMessageSession] {
        try await diagnosed(
            operation: "private_sessions",
            successDetails: { ["sessions": String($0.count)] }
        ) {
            try requireLoggedIn()
            let query = try await api.signedWBIQuery([
                "session_type": "1",
                "group_fold": "1",
                "unfollow_fold": "0",
                "sort_rule": "2",
                "build": "0",
                "mobi_app": "web"
            ])
            let data = try await request(
                base: privateMessageBaseURL,
                path: "/session_svr/v1/session_svr/get_sessions",
                query: query,
                referer: "https://message.bilibili.com/"
            )

            let talkerIDs = try AccountMessagePayloadDecoder.privateMessageTalkerIDs(from: data)
            var actors: [Int: AccountMessageActor] = [:]
            if !talkerIDs.isEmpty {
                let userQuery = try await api.signedWBIQuery([
                    "uids": talkerIDs.map(String.init).joined(separator: ","),
                    "build": "0",
                    "mobi_app": "web"
                ])
                if let userData = try? await request(
                    base: privateMessageBaseURL,
                    path: "/account/v1/user/cards",
                    query: userQuery,
                    referer: "https://message.bilibili.com/"
                ) {
                    actors = (try? AccountMessagePayloadDecoder.privateMessageActors(from: userData)) ?? [:]
                }
            }

            return try AccountMessagePayloadDecoder.privateMessageSessions(
                from: data,
                actors: actors,
                currentUserMID: currentUserMID()
            )
        }
    }

    func fetchPrivateMessages(
        talkerID: Int,
        endSequence: Int? = nil,
        pageSize: Int = 20
    ) async throws -> AccountPrivateMessagePage {
        try await diagnosed(
            operation: "private_messages",
            details: ["page": endSequence == nil ? "latest" : "history"],
            successDetails: {
                ["items": String($0.items.count), "hasMore": String($0.hasMore)]
            }
        ) {
            try requireLoggedIn()
            guard talkerID > 0 else {
                throw BiliAPIError.api(code: -1, message: "私信用户无效")
            }
            var query = [
                "talker_id": String(talkerID),
                "session_type": "1",
                "size": String(max(1, min(pageSize, 50))),
                "sender_device_id": "1",
                "build": "0",
                "mobi_app": "web",
                "web_location": "333.1296"
            ]
            if let endSequence, endSequence > 0 {
                query["begin_seqno"] = "0"
                query["end_seqno"] = String(endSequence)
            }
            let signedQuery = try await api.signedWBIQuery(query)
            let data = try await request(
                base: privateMessageBaseURL,
                path: "/svr_sync/v1/svr_sync/fetch_session_msgs",
                query: signedQuery,
                referer: "https://message.bilibili.com/"
            )
            return try AccountMessagePayloadDecoder.privateMessages(
                from: data,
                currentUserMID: currentUserMID()
            )
        }
    }

    func markPrivateMessageSessionRead(talkerID: Int, ackSequence: Int) async throws {
        try await diagnosed(operation: "private_read_ack") {
            try requireLoggedIn()
            guard talkerID > 0, ackSequence > 0 else {
                throw BiliAPIError.api(code: -1, message: "私信已读参数无效")
            }
            let csrf = try requireCSRF()
            let query = try await api.signedWBIQuery([
                "talker_id": String(talkerID),
                "session_type": "1",
                "ack_seqno": String(ackSequence),
                "build": "0",
                "mobi_app": "web",
                "csrf_token": csrf,
                "csrf": csrf
            ])
            let data = try await request(
                base: privateMessageBaseURL,
                path: "/session_svr/v1/session_svr/update_ack",
                query: query,
                referer: "https://message.bilibili.com/"
            )
            try AccountMessagePayloadDecoder.validateAcknowledgement(from: data)
        }
    }

    func sendPrivateTextMessage(talkerID: Int, text: String) async throws {
        try await diagnosed(
            operation: "private_send_text",
            details: ["characters": String(text.count)]
        ) {
            try requireLoggedIn()
            guard talkerID > 0 else {
                throw BiliAPIError.api(code: -1, message: "私信用户无效")
            }
            guard let senderID = currentUserMID(), senderID > 0 else {
                throw BiliAPIError.api(code: -1, message: "无法识别当前账号")
            }
            let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                throw BiliAPIError.api(code: -1, message: "请输入私信内容")
            }
            guard content.count <= 1_000 else {
                throw BiliAPIError.api(code: -1, message: "私信内容不能超过 1000 个字")
            }
            try await sendPrivateMessage(
                senderID: senderID,
                talkerID: talkerID,
                messageType: 1,
                contentObject: ["content": content]
            )
        }
    }

    func sendPrivateImageMessage(talkerID: Int, imageData: Data) async throws {
        try await diagnosed(
            operation: "private_send_image",
            details: ["bytes": String(imageData.count)]
        ) {
            try requireLoggedIn()
            guard talkerID > 0 else {
                throw BiliAPIError.api(code: -1, message: "私信用户无效")
            }
            guard let senderID = currentUserMID(), senderID > 0 else {
                throw BiliAPIError.api(code: -1, message: "无法识别当前账号")
            }
            guard !imageData.isEmpty, imageData.count <= 20 * 1_024 * 1_024 else {
                throw BiliAPIError.api(code: -1, message: "图片大小不能超过 20 MB")
            }

            let upload = try await uploadPrivateMessageImage(imageData)
            try await sendPrivateMessage(
                senderID: senderID,
                talkerID: talkerID,
                messageType: 2,
                contentObject: [
                    "url": upload.url,
                    "height": upload.height,
                    "width": upload.width,
                    "imageType": "jpg",
                    "original": 1,
                    "size": upload.size
                ]
            )
        }
    }

    func withdrawPrivateMessage(talkerID: Int, messageKey: Int) async throws {
        try await diagnosed(operation: "private_message_withdraw") {
            try requireLoggedIn()
            guard talkerID > 0, messageKey > 0 else {
                throw BiliAPIError.api(code: -1, message: "撤回消息参数无效")
            }
            guard let senderID = currentUserMID(), senderID > 0 else {
                throw BiliAPIError.api(code: -1, message: "无法识别当前账号")
            }
            try await sendPrivateMessage(
                senderID: senderID,
                talkerID: talkerID,
                messageType: 5,
                content: String(messageKey)
            )
        }
    }

    func reportPrivateMessage(
        accusedUserID: Int,
        messageKey: Int,
        reasonType: Int,
        reasonDescription: String
    ) async throws {
        try await diagnosed(
            operation: "private_message_report",
            details: ["reason": String(reasonType)]
        ) {
            try requireLoggedIn()
            guard accusedUserID > 0, messageKey > 0 else {
                throw BiliAPIError.api(code: -1, message: "举报消息参数无效")
            }
            let description = reasonDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            guard reasonType != 0 || !description.isEmpty else {
                throw BiliAPIError.api(code: -1, message: "请填写举报原因")
            }
            let csrf = try requireCSRF()
            let comment = try encodedJSONString([
                "group_id": 0,
                "msg_key": String(messageKey)
            ])
            let extra = try encodedJSONString(["msg_keys": [String]()])
            let data = try await postForm(
                base: privateMessageBaseURL,
                path: "/x/bplus/im/report/add",
                body: [
                    "biz_code": "4",
                    "accused_uid": String(accusedUserID),
                    "object_id": String(accusedUserID),
                    "reason_type": String(reasonType),
                    "reason_desc": description,
                    "module": "604",
                    "comment": comment,
                    "extra": extra,
                    "csrf": csrf
                ],
                referer: "https://message.bilibili.com/"
            )
            try AccountMessagePayloadDecoder.validateAcknowledgement(from: data)
        }
    }

    func setPrivateMessageSessionPinned(talkerID: Int, pinned: Bool) async throws {
        try await diagnosed(
            operation: "private_session_pin",
            details: ["action": pinned ? "pin" : "unpin"]
        ) {
            try requireLoggedIn()
            guard talkerID > 0 else {
                throw BiliAPIError.api(code: -1, message: "私信用户无效")
            }
            let csrf = try requireCSRF()
            let body = try await api.signedWBIQuery([
                "talker_id": String(talkerID),
                "session_type": "1",
                "op_type": pinned ? "1" : "0",
                "build": "0",
                "mobi_app": "web",
                "csrf_token": csrf,
                "csrf": csrf
            ])
            let data = try await postForm(
                base: privateMessageBaseURL,
                path: "/session_svr/v1/session_svr/set_top",
                body: body,
                referer: "https://message.bilibili.com/"
            )
            try AccountMessagePayloadDecoder.validateAcknowledgement(from: data)
        }
    }

    func setPrivateMessageSessionMuted(talkerID: Int, muted: Bool) async throws {
        try await diagnosed(
            operation: "private_session_mute",
            details: ["action": muted ? "mute" : "unmute"]
        ) {
            try requireLoggedIn()
            guard talkerID > 0 else {
                throw BiliAPIError.api(code: -1, message: "私信用户无效")
            }
            guard let currentUserMID = currentUserMID(), currentUserMID > 0 else {
                throw BiliAPIError.api(code: -1, message: "无法识别当前账号")
            }
            let csrf = try requireCSRF()
            let data = try await postForm(
                base: privateMessageBaseURL,
                path: "/link_setting/v1/link_setting/set_msg_dnd",
                body: [
                    "uid": String(currentUserMID),
                    "setting": muted ? "1" : "0",
                    "dnd_uid": String(talkerID),
                    "build": "0",
                    "mobi_app": "web",
                    "csrf_token": csrf,
                    "csrf": csrf
                ],
                referer: "https://message.bilibili.com/"
            )
            try AccountMessagePayloadDecoder.validateAcknowledgement(from: data)
        }
    }

    func removePrivateMessageSession(talkerID: Int) async throws {
        try await diagnosed(operation: "private_session_remove") {
            try requireLoggedIn()
            guard talkerID > 0 else {
                throw BiliAPIError.api(code: -1, message: "私信用户无效")
            }
            let csrf = try requireCSRF()
            let body = try await api.signedWBIQuery([
                "talker_id": String(talkerID),
                "session_type": "1",
                "build": "0",
                "mobi_app": "web",
                "csrf_token": csrf,
                "csrf": csrf
            ])
            let data = try await postForm(
                base: privateMessageBaseURL,
                path: "/session_svr/v1/session_svr/remove_session",
                body: body,
                referer: "https://message.bilibili.com/"
            )
            try AccountMessagePayloadDecoder.validateAcknowledgement(from: data)
        }
    }

    func resolveRoute(for item: AccountMessageItem) async -> AccountMessageRouteResolution {
        let startedAt = Date()

        if let target = item.commentTarget {
            if target.type != 1 {
                diagnostics.record(
                    operation: "route_resolve",
                    startedAt: startedAt,
                    outcome: "comment",
                    details: ["type": String(target.type)]
                )
                return .comment(target)
            }

            do {
                let thread = try await fetchCommentThread(for: target)
                if thread.requestedReplyWasUnavailable {
                    diagnostics.record(
                        operation: "route_resolve",
                        startedAt: startedAt,
                        outcome: "comment_unavailable",
                        details: ["type": String(target.type)]
                    )
                    return .unavailable(
                        AccountMessageUnavailableTarget(
                            id: item.id,
                            title: "目标回复暂时不可见",
                            message: "这条回复可能已被删除、折叠，或者仅对部分用户可见。不会继续跳转到没有目标位置的视频页。",
                            originalURL: target.originalURL
                        )
                    )
                }
            } catch {
                diagnostics.record(
                    operation: "route_resolve",
                    startedAt: startedAt,
                    outcome: "comment_unavailable",
                    details: ["type": String(target.type)]
                )
                return .unavailable(
                    AccountMessageUnavailableTarget(
                        id: item.id,
                        title: "评论暂时不可见",
                        message: "评论可能已被删除、折叠，或者当前账号没有查看权限。不会继续跳转到空白评论位置。",
                        originalURL: target.originalURL
                    )
                )
            }
        }

        guard let routeURL = item.routeURL ?? item.commentTarget?.originalURL else {
            let unavailable = AccountMessageUnavailableTarget(
                id: item.id,
                title: "没有可用的跳转目标",
                message: "这条通知没有提供原内容地址，暂时无法继续打开。",
                originalURL: nil
            )
            diagnostics.record(
                operation: "route_resolve",
                startedAt: startedAt,
                outcome: "missing"
            )
            return .unavailable(unavailable)
        }

        do {
            try await validateOriginalContent(at: routeURL)
            diagnostics.record(
                operation: "route_resolve",
                startedAt: startedAt,
                outcome: "open",
                details: ["kind": contentKind(for: routeURL)]
            )
            return .open(routeURL)
        } catch {
            diagnostics.record(
                operation: "route_resolve",
                startedAt: startedAt,
                outcome: "unavailable",
                details: ["kind": contentKind(for: routeURL)]
            )
            return .unavailable(
                AccountMessageUnavailableTarget(
                    id: item.id,
                    title: "原内容暂时无法访问",
                    message: "内容可能已被删除、设为不可见，或者当前网络无法完成验证。不会继续跳转到空白详情页。",
                    originalURL: routeURL
                )
            )
        }
    }

    func fetchCommentThread(for target: AccountMessageCommentTarget) async throws -> AccountMessageCommentThread {
        try await diagnosed(
            operation: "comment_target",
            details: ["type": String(target.type)],
            successDetails: {
                [
                    "replies": String($0.replies.count),
                    "focused": $0.focusedReplyID == nil ? "no" : "yes"
                ]
            }
        ) {
            let firstPage = try await api.fetchCommentReplies(
                oid: target.oid,
                type: target.type,
                root: target.rootID,
                page: 1
            )
            guard let root = firstPage.root
                ?? firstPage.replies?.first(where: { $0.id == target.rootID })
            else {
                throw AccountMessageRouteError.commentUnavailable
            }

            var replies = firstPage.replies ?? []
            if let secondaryID = target.secondaryID,
               secondaryID != target.rootID,
               !replies.contains(where: { $0.id == secondaryID }) {
                let pageNumbers = VideoDetailCommentDeepLinkResolution.additionalPageNumbers(
                    replyCount: root.replyCount ?? replies.count,
                    knownReplyIDs: Set(replies.map(\.id)),
                    targetReplyID: secondaryID
                )
                for pageNumber in pageNumbers {
                    let page = try await api.fetchCommentReplies(
                        oid: target.oid,
                        type: target.type,
                        root: target.rootID,
                        page: pageNumber
                    )
                    let pageReplies = page.replies ?? []
                    guard !pageReplies.isEmpty else { break }
                    var seen = Set(replies.map(\.id))
                    replies.append(contentsOf: pageReplies.filter { seen.insert($0.id).inserted })
                    if replies.contains(where: { $0.id == secondaryID }) {
                        break
                    }
                }
            }

            let focusedReplyID = VideoDetailCommentDeepLinkResolution.focusedReplyID(
                requestedReplyID: target.secondaryID,
                rootID: target.rootID,
                replies: replies
            )
            let requestedReplyWasUnavailable = target.secondaryID.map {
                $0 != target.rootID && focusedReplyID == nil
            } ?? false
            return AccountMessageCommentThread(
                root: root,
                replies: replies,
                focusedReplyID: focusedReplyID,
                requestedReplyWasUnavailable: requestedReplyWasUnavailable
            )
        }
    }

    func markAllNotificationsRead() async throws {
        try await diagnosed(operation: "mark_all_read") {
            var firstError: Error?
            for category in AccountMessageCategory.allCases {
                do {
                    _ = try await fetchPage(category: category)
                } catch {
                    firstError = firstError ?? error
                }
            }
            if let firstError {
                throw firstError
            }
        }
    }

    func delete(_ item: AccountMessageItem) async throws {
        try requireLoggedIn()
        guard let serverID = item.serverID else {
            throw BiliAPIError.api(code: -1, message: "这条通知缺少服务端 ID")
        }
        let csrf = try requireCSRF()

        if item.category == .system {
            let data = try await postJSON(
                base: messageBaseURL,
                path: "/x/sys-msg/del_notify_list",
                query: ["mobi_app": "android", "csrf": csrf],
                body: [
                    "csrf": csrf,
                    "ids": [serverID],
                    "station_ids": [],
                    "type": 4,
                    "mobi_app": "android"
                ],
                referer: "https://message.bilibili.com"
            )
            try AccountMessagePayloadDecoder.validateAcknowledgement(from: data)
            return
        }

        let type: Int
        switch item.category {
        case .like:
            type = 0
        case .reply:
            type = 1
        case .mention:
            type = 2
        case .system:
            return
        }
        let data = try await postForm(
            base: apiBaseURL,
            path: "/x/msgfeed/del",
            body: [
                "tp": String(type),
                "id": String(serverID),
                "build": "0",
                "mobi_app": "web",
                "csrf_token": csrf,
                "csrf": csrf
            ]
        )
        try AccountMessagePayloadDecoder.validateAcknowledgement(from: data)
    }

    func setLikeNotificationMuted(_ muted: Bool, for item: AccountMessageItem) async throws {
        try requireLoggedIn()
        guard item.category == .like, let serverID = item.serverID else {
            throw BiliAPIError.api(code: -1, message: "这条点赞通知无法设置")
        }
        let csrf = try requireCSRF()
        let data = try await postForm(
            base: apiBaseURL,
            path: "/x/msgfeed/notice",
            body: [
                "mobi_app": "web",
                "platform": "web",
                "tp": "0",
                "id": String(serverID),
                "notice_state": muted ? "1" : "0",
                "build": "0",
                "csrf_token": csrf,
                "csrf": csrf
            ]
        )
        try AccountMessagePayloadDecoder.validateAcknowledgement(from: data)
    }

    private func updateSystemReadCursor(_ cursor: Int) async throws {
        guard cursor > 0 else { return }
        guard let csrf = sessionStore.csrfToken(), !csrf.isEmpty else {
            throw BiliAPIError.missingCSRF
        }
        let data = try await request(
            base: messageBaseURL,
            path: "/x/sys-msg/update_cursor",
            query: ["csrf": csrf, "cursor": String(cursor)],
            referer: "https://message.bilibili.com"
        )
        try AccountMessagePayloadDecoder.validateAcknowledgement(from: data)
    }

    private func validateOriginalContent(at url: URL) async throws {
        if let videoLink = BiliVideoLink(url: url) {
            if let bvid = videoLink.bvid {
                _ = try await api.fetchVideoDetail(bvid: bvid)
                return
            }
            if let aid = videoLink.aid {
                _ = try await api.fetchVideoDetail(aid: aid)
                return
            }
        }

        let host = url.host?.lowercased() ?? ""
        let components = url.pathComponents
            .dropFirst()
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }

        if host.contains("live.bilibili.com"),
           let roomID = components.compactMap(Int.init).first {
            _ = try await api.fetchLiveRoomInfo(roomID: roomID)
            return
        }

        if host == "t.bilibili.com" || components.first?.lowercased() == "opus",
           let dynamicID = components.last.flatMap(Int.init) {
            let data = try await request(
                base: apiBaseURL,
                path: "/x/polymer/web-dynamic/v1/detail",
                query: [
                    "id": String(dynamicID),
                    "features": "itemOpusStyle,opusBigCover,onlyfansVote"
                ]
            )
            try validateGenericPayload(data, requiredNestedKey: "item")
            return
        }

        if components.first?.lowercased() == "read",
           let articleComponent = components.dropFirst().first,
           let articleID = Int(articleComponent.lowercased().replacingOccurrences(of: "cv", with: "")) {
            let data = try await request(
                base: apiBaseURL,
                path: "/x/article/viewinfo",
                query: ["id": String(articleID), "mobi_app": "pc", "from": "web"]
            )
            try validateGenericPayload(data)
        }
    }

    private func validateGenericPayload(_ data: Data, requiredNestedKey: String? = nil) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BiliAPIError.missingPayload
        }
        let code: Int = {
            if let value = object["code"] as? Int { return value }
            if let value = object["code"] as? NSNumber { return value.intValue }
            if let value = object["code"] as? String { return Int(value) ?? -1 }
            return -1
        }()
        guard code == 0 else {
            throw BiliAPIError.api(
                code: code,
                message: object["message"] as? String ?? object["msg"] as? String
            )
        }
        guard let payload = object["data"], !(payload is NSNull) else {
            throw BiliAPIError.missingPayload
        }
        if let requiredNestedKey {
            guard let dictionary = payload as? [String: Any],
                  let value = dictionary[requiredNestedKey],
                  !(value is NSNull)
            else {
                throw BiliAPIError.missingPayload
            }
        }
    }

    private func contentKind(for url: URL) -> String {
        if BiliVideoLink(url: url) != nil { return "video" }
        let host = url.host?.lowercased() ?? ""
        if host.contains("live.bilibili.com") { return "live" }
        if host == "t.bilibili.com" || url.path.lowercased().contains("/opus/") { return "dynamic" }
        if url.path.lowercased().contains("/read/") { return "article" }
        return "web"
    }

    private func diagnosed<T>(
        operation: String,
        details: [String: String] = [:],
        successDetails: (T) -> [String: String] = { _ in [:] },
        action: () async throws -> T
    ) async throws -> T {
        let startedAt = Date()
        do {
            let value = try await action()
            diagnostics.record(
                operation: operation,
                startedAt: startedAt,
                outcome: "success",
                details: details.merging(successDetails(value)) { _, new in new }
            )
            return value
        } catch is CancellationError {
            diagnostics.record(
                operation: operation,
                startedAt: startedAt,
                outcome: "cancelled",
                details: details
            )
            throw CancellationError()
        } catch {
            diagnostics.record(
                operation: operation,
                startedAt: startedAt,
                outcome: "failure",
                details: details.merging(diagnosticErrorDetails(error)) { _, new in new }
            )
            throw error
        }
    }

    private func diagnosticErrorDetails(_ error: Error) -> [String: String] {
        var details = ["error": String(describing: type(of: error))]
        if let error = error as? BiliAPIError,
           case .api(let code, _) = error {
            details["code"] = String(code)
        }
        return details
    }

    private func standardFeedQuery() -> [String: String] {
        [
            "platform": "web",
            "mobi_app": "web",
            "build": "0",
            "web_location": "333.40164"
        ]
    }

    private func requireLoggedIn() throws {
        guard sessionStore.isLoggedIn else {
            throw BiliAPIError.missingSESSDATA
        }
    }

    private func requireCSRF() throws -> String {
        guard let csrf = sessionStore.csrfToken(), !csrf.isEmpty else {
            throw BiliAPIError.missingCSRF
        }
        return csrf
    }

    private func currentUserMID() -> Int? {
        if let mid = sessionStore.user?.mid, mid > 0 {
            return mid
        }
        return sessionStore.cookieHeader()
            .split(separator: ";")
            .compactMap { item -> Int? in
                let pair = item.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard pair.count == 2, pair[0] == "DedeUserID" else { return nil }
                return Int(pair[1])
            }
            .first
    }

    private func privateMessageDeviceID() -> String {
        let key = "cc.bili.accountMessage.privateDeviceID.v1"
        if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
            return value
        }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    private func uploadPrivateMessageImage(_ imageData: Data) async throws -> AccountPrivateMessageImageUpload {
        try await diagnosed(
            operation: "private_image_upload",
            details: ["bytes": String(imageData.count)],
            successDetails: {
                ["width": String($0.width), "height": String($0.height)]
            }
        ) {
            let csrf = try requireCSRF()
            let data = try await postMultipart(
                base: apiBaseURL,
                path: "/x/dynamic/feed/draw/upload_bfs",
                fields: [
                    "biz": "im",
                    "csrf": csrf
                ],
                fileField: "file_up",
                fileName: "message.jpg",
                mimeType: "image/jpeg",
                fileData: imageData,
                referer: "https://message.bilibili.com/"
            )
            return try AccountMessagePayloadDecoder.privateMessageImageUpload(from: data)
        }
    }

    private func sendPrivateMessage(
        senderID: Int,
        talkerID: Int,
        messageType: Int,
        contentObject: [String: Any]
    ) async throws {
        try await sendPrivateMessage(
            senderID: senderID,
            talkerID: talkerID,
            messageType: messageType,
            content: try encodedJSONString(contentObject)
        )
    }

    private func sendPrivateMessage(
        senderID: Int,
        talkerID: Int,
        messageType: Int,
        content: String
    ) async throws {
        let csrf = try requireCSRF()
        let deviceID = privateMessageDeviceID()
        let signedQuery = try await api.signedWBIQuery([
            "w_sender_uid": String(senderID),
            "w_receiver_id": String(talkerID),
            "w_dev_id": deviceID
        ])
        let data = try await postForm(
            base: privateMessageBaseURL,
            path: "/web_im/v1/web_im/send_msg",
            query: signedQuery,
            body: [
                "msg[sender_uid]": String(senderID),
                "msg[receiver_id]": String(talkerID),
                "msg[receiver_type]": "1",
                "msg[msg_type]": String(messageType),
                "msg[msg_status]": "0",
                "msg[dev_id]": deviceID,
                "msg[timestamp]": String(Int(Date().timeIntervalSince1970)),
                "msg[new_face_version]": "1",
                "msg[content]": content,
                "from_firework": "0",
                "build": "0",
                "mobi_app": "web",
                "csrf_token": csrf,
                "csrf": csrf
            ],
            referer: "https://message.bilibili.com/"
        )
        try AccountMessagePayloadDecoder.validateAcknowledgement(from: data)
    }

    private func encodedJSONString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }

    private func request(
        base: URL,
        path: String,
        query: [String: String],
        referer: String = "https://www.bilibili.com"
    ) async throws -> Data {
        let request = try makeRequest(base: base, path: path, query: query, referer: referer)
        return try await execute(request)
    }

    private func postForm(
        base: URL,
        path: String,
        query: [String: String] = [:],
        body: [String: String],
        referer: String = "https://www.bilibili.com"
    ) async throws -> Data {
        var request = try makeRequest(base: base, path: path, query: query, referer: referer)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = body.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        return try await execute(request)
    }

    private func postJSON(
        base: URL,
        path: String,
        query: [String: String],
        body: [String: Any],
        referer: String
    ) async throws -> Data {
        var request = try makeRequest(base: base, path: path, query: query, referer: referer)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(request)
    }

    private func postMultipart(
        base: URL,
        path: String,
        query: [String: String] = [:],
        fields: [String: String],
        fileField: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        referer: String
    ) async throws -> Data {
        let boundary = "CiliCiliBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            body.append(contentsOf: "--\(boundary)\r\n".utf8)
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8)
            body.append(contentsOf: "\(value)\r\n".utf8)
        }
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n".utf8)
        body.append(contentsOf: "Content-Type: \(mimeType)\r\n\r\n".utf8)
        body.append(fileData)
        body.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)

        var request = try makeRequest(base: base, path: path, query: query, referer: referer)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.httpBody = body
        return try await execute(request)
    }

    private func makeRequest(
        base: URL,
        path: String,
        query: [String: String],
        referer: String
    ) throws -> URLRequest {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw BiliAPIError.invalidURL
        }
        components.path = path
        components.queryItems = query
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            throw BiliAPIError.invalidURL
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.networkServiceType = .responsiveData
        request.timeoutInterval = 12
        request.allHTTPHeaderFields = BiliURLSessionFactory.apiHeaders(
            referer: referer,
            userAgent: nil,
            cookieHeader: sessionStore.cookieHeader()
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await BiliNetworkRetry.data(
            session: session,
            request: request,
            priority: URLSessionTask.highPriority,
            policy: .api
        )
        guard let response = response as? HTTPURLResponse,
              (200 ... 299).contains(response.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw BiliAPIError.api(
                code: statusCode,
                message: statusCode > 0 ? HTTPURLResponse.localizedString(forStatusCode: statusCode) : nil
            )
        }
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        return data
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.waitsForConnectivity = true
        configuration.networkServiceType = .responsiveData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 30
        configuration.httpAdditionalHeaders = BiliURLSessionFactory.apiHeaders(
            referer: "https://www.bilibili.com",
            userAgent: nil,
            cookieHeader: ""
        )
        return URLSession(configuration: configuration)
    }
}

nonisolated enum AccountMessagePayloadDecoder {
    static func unreadSummary(from data: Data) throws -> AccountMessageUnreadSummary {
        let payload: UnreadPayload = try payload(from: data)
        return AccountMessageUnreadSummary(
            reply: payload.reply?.value ?? 0,
            mention: payload.at?.value ?? 0,
            like: payload.like?.value ?? 0,
            system: payload.system?.value ?? 0
        )
    }

    static func privateMessageUnreadCount(from data: Data) throws -> Int {
        let payload: PrivateSessionListPayload = try payload(from: data)
        return (payload.sessionList ?? []).reduce(into: 0) { total, item in
            total += max(0, item.unreadCount?.value ?? 0)
        }
    }

    static func accountMessageInlineEmotes(from data: Data) throws -> [String: BiliInlineEmote] {
        let payload: AccountMessageEmotePanelPayload = try payload(from: data)
        return (payload.packages ?? [])
            .flatMap { $0.emotes ?? [] }
            .reduce(into: [String: BiliInlineEmote]()) { emotes, item in
                guard let token = item.text.nonEmptyAccountMessageText,
                      let url = item.url.nonEmptyAccountMessageText,
                      emotes[token] == nil
                else {
                    return
                }
                emotes[token] = BiliInlineEmote(token: token, url: url)
            }
    }

    static func page(
        category: AccountMessageCategory,
        from data: Data,
        pageSize: Int
    ) throws -> AccountMessagePage {
        switch category {
        case .reply:
            let payload: ReplyPayload = try payload(from: data)
            let cursor = payload.cursor?.messageCursor
            let items = (payload.items ?? []).map(replyItem)
            return AccountMessagePage(
                items: items,
                nextCursor: cursor,
                hasMore: hasMore(cursor: cursor, itemCount: items.count),
                lastViewAt: date(unixTime: payload.lastViewAt?.value)
            )

        case .mention:
            let payload: MentionPayload = try payload(from: data)
            let cursor = payload.cursor?.messageCursor
            let items = (payload.items ?? []).map(mentionItem)
            return AccountMessagePage(
                items: items,
                nextCursor: cursor,
                hasMore: hasMore(cursor: cursor, itemCount: items.count),
                lastViewAt: date(unixTime: payload.lastViewAt?.value)
            )

        case .like:
            let payload: LikePayload = try payload(from: data)
            let latest = payload.latest?.items ?? []
            let total = payload.total?.items ?? []
            let latestItems = latest.map { likeItem($0, isLatest: true) }
            let existingIDs = Set(latestItems.map(\.id))
            let totalItems = total
                .map { likeItem($0, isLatest: false) }
                .filter { existingIDs.contains($0.id) == false }
            let items = latestItems + totalItems
            let cursor = payload.total?.cursor?.messageCursor
            return AccountMessagePage(
                items: items,
                nextCursor: cursor,
                hasMore: hasMore(cursor: cursor, itemCount: totalItems.count),
                lastViewAt: date(unixTime: payload.latest?.lastViewAt?.value)
            )

        case .system:
            let items: [SystemPayload] = try payload(from: data)
            let normalizedItems = items.map(systemItem)
            let lastCursor = items.last?.cursor?.value
            let cursor = lastCursor.map { AccountMessageCursor(id: $0, timestamp: nil, isEnd: normalizedItems.count < pageSize) }
            return AccountMessagePage(
                items: normalizedItems,
                nextCursor: cursor,
                hasMore: normalizedItems.count >= pageSize && cursor?.canLoadMore == true
            )
        }
    }

    static func likeDetail(from data: Data) throws -> AccountMessageLikeDetailPage {
        let payload: LikeDetailPayload = try payload(from: data)
        let items = (payload.items ?? []).compactMap { item -> AccountMessageLikeDetailItem? in
            guard let actor = actor(item.user) else { return nil }
            return AccountMessageLikeDetailItem(
                actor: actor,
                timestamp: date(unixTime: item.likeTime?.value)
            )
        }
        return AccountMessageLikeDetailPage(
            title: payload.card?.title.nonEmptyAccountMessageText,
            items: items,
            hasMore: !(payload.page?.isEnd ?? items.isEmpty),
            nextLastMID: items.last?.actor.mid
        )
    }

    static func followers(
        from data: Data,
        page: Int,
        pageSize: Int
    ) throws -> AccountMessageFollowerPage {
        let payload: FollowersPayload = try payload(from: data)
        let items = (payload.list ?? []).compactMap { item -> AccountMessageFollower? in
            guard let mid = item.mid?.value, mid > 0 else { return nil }
            let actor = AccountMessageActor(
                mid: mid,
                name: item.uname.nonEmptyAccountMessageText ?? "用户",
                avatarURLString: normalizedImageURL(item.face)
            )
            return AccountMessageFollower(
                actor: actor,
                sign: item.sign.nonEmptyAccountMessageText,
                followedAt: date(unixTime: item.mtime?.value)
            )
        }
        let total = payload.total?.value
        let reachedTotal = total.map { page * pageSize >= $0 } ?? false
        let hasMore = !items.isEmpty
            && items.count >= pageSize
            && !reachedTotal
        return AccountMessageFollowerPage(items: items, total: total, hasMore: hasMore)
    }

    static func privateMessageTalkerIDs(from data: Data) throws -> [Int] {
        let payload: PrivateSessionListPayload = try payload(from: data)
        var seen = Set<Int>()
        return (payload.sessionList ?? []).compactMap { item in
            guard let talkerID = item.talkerID?.value,
                  talkerID > 0,
                  seen.insert(talkerID).inserted
            else {
                return nil
            }
            return talkerID
        }
    }

    static func privateMessageActors(from data: Data) throws -> [Int: AccountMessageActor] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BiliAPIError.missingPayload
        }
        let code = integer(object["code"]) ?? -1
        guard code == 0 else {
            throw BiliAPIError.api(
                code: code,
                message: object["message"] as? String ?? object["msg"] as? String
            )
        }

        let rawData = object["data"]
        let values: [[String: Any]]
        if let array = rawData as? [[String: Any]] {
            values = array
        } else if let dictionary = rawData as? [String: Any] {
            if let cards = dictionary["cards"] as? [[String: Any]] {
                values = cards
            } else if let cards = dictionary["cards"] as? [String: [String: Any]] {
                values = cards.map { key, value in
                    var value = value
                    value["mid"] = value["mid"] ?? key
                    return value
                }
            } else {
                values = dictionary.compactMap { key, rawValue in
                    guard var value = rawValue as? [String: Any] else { return nil }
                    value["mid"] = value["mid"] ?? key
                    return value
                }
            }
        } else {
            throw BiliAPIError.missingPayload
        }

        return values.reduce(into: [Int: AccountMessageActor]()) { result, value in
            guard let mid = integer(value["mid"]), mid > 0 else { return }
            let name = string(value["name"])
                ?? string(value["uname"])
                ?? "用户 \(mid)"
            let avatar = normalizedImageURL(
                string(value["face"])
                    ?? string(value["pic_url"])
                    ?? string(value["avatar"])
            )
            result[mid] = AccountMessageActor(mid: mid, name: name, avatarURLString: avatar)
        }
    }

    static func privateMessageSessions(
        from data: Data,
        actors: [Int: AccountMessageActor],
        currentUserMID: Int?
    ) throws -> [AccountPrivateMessageSession] {
        let payload: PrivateSessionListPayload = try payload(from: data)
        return (payload.sessionList ?? []).compactMap { item in
            guard let talkerID = item.talkerID?.value, talkerID > 0 else { return nil }
            let embeddedActor = item.accountInfo.map {
                AccountMessageActor(
                    mid: talkerID,
                    name: $0.name.nonEmptyAccountMessageText ?? "用户 \(talkerID)",
                    avatarURLString: normalizedImageURL($0.picURL)
                )
            }
            let actor = actors[talkerID]
                ?? embeddedActor
                ?? AccountMessageActor(mid: talkerID, name: "用户 \(talkerID)", avatarURLString: nil)
            let content = PrivateMessageContent(rawValue: item.lastMessage?.content, type: item.lastMessage?.msgType?.value)
            let senderID = item.lastMessage?.senderUID?.value
            let preview = senderID == currentUserMID ? "我：\(content.text)" : content.text
            return AccountPrivateMessageSession(
                talkerID: talkerID,
                actor: actor,
                preview: preview,
                timestamp: date(unixTime: item.lastMessage?.timestamp?.value ?? item.sessionTimestamp?.value),
                unreadCount: max(0, item.unreadCount?.value ?? 0),
                lastMessageSequence: item.lastMessage?.sequence?.value,
                isPinned: (item.topTimestamp?.value ?? 0) > 0,
                isMuted: (item.isDND?.value ?? 0) == 1
            )
        }
    }

    static func privateMessages(
        from data: Data,
        currentUserMID: Int?
    ) throws -> AccountPrivateMessagePage {
        let payload: PrivateMessagePagePayload = try payload(from: data)
        let items = (payload.messages ?? []).compactMap { item -> AccountPrivateMessage? in
            guard let sequence = item.sequence?.value,
                  sequence > 0,
                  let senderID = item.senderUID?.value
            else {
                return nil
            }
            let messageType = item.msgType?.value ?? 0
            guard messageType != 5 else { return nil }
            let isWithdrawn = (item.msgStatus?.value ?? 0) == 1
            let content = PrivateMessageContent(rawValue: item.content, type: messageType)
            return AccountPrivateMessage(
                sequence: sequence,
                messageKey: item.messageKey?.value,
                messageType: messageType,
                senderID: senderID,
                text: isWithdrawn ? "[消息已撤回]" : content.text,
                imageURLString: isWithdrawn ? nil : normalizedImageURL(content.imageURLString),
                routeURL: isWithdrawn ? nil : content.routeURL,
                timestamp: date(unixTime: item.timestamp?.value),
                isOutgoing: senderID == currentUserMID,
                isWithdrawn: isWithdrawn
            )
        }
        .sorted { $0.sequence < $1.sequence }

        return AccountPrivateMessagePage(
            items: items,
            hasMore: (payload.hasMore?.value ?? 0) != 0 && !items.isEmpty,
            nextEndSequence: items.first?.sequence
        )
    }

    static func privateMessageImageUpload(from data: Data) throws -> AccountPrivateMessageImageUpload {
        let payload: PrivateImageUploadPayload = try payload(from: data)
        guard let rawURL = payload.imageURL.nonEmptyAccountMessageText else {
            throw BiliAPIError.missingPayload
        }
        return AccountPrivateMessageImageUpload(
            url: rawURL.normalizedBiliURL(),
            width: max(0, payload.imageWidth ?? 0),
            height: max(0, payload.imageHeight ?? 0),
            size: max(0, payload.imageSize ?? 0)
        )
    }

    static func newestSystemCursor(from data: Data) -> Int? {
        let items: [SystemPayload]? = try? payload(from: data)
        return items?.first?.cursor?.value
    }

    static func validateAcknowledgement(from data: Data) throws {
        let response = try JSONDecoder().decode(BiliResponse<AcknowledgementPayload>.self, from: data)
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }

    private static func payload<T: Decodable>(from data: Data) throws -> T {
        let response = try JSONDecoder().decode(BiliResponse<T>.self, from: data)
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let payload = response.payload else {
            throw BiliAPIError.missingPayload
        }
        return payload
    }

    private static func hasMore(
        cursor: AccountMessageCursor?,
        itemCount: Int
    ) -> Bool {
        guard itemCount > 0 else { return false }
        guard let cursor else { return false }
        return cursor.canLoadMore
    }

    private static func replyItem(_ payload: ReplyItemPayload) -> AccountMessageItem {
        let messageActor = actor(payload.user)
        let actorName = messageActor?.name ?? "有人"
        let count = payload.counts?.value ?? 1
        let isMultiple = payload.isMulti?.value == 1 || count > 1
        let title = isMultiple ? "\(actorName) 等 \(count) 人回复了你" : "\(actorName) 回复了你"
        let target = payload.item?.targetReplyContent.nonEmptyAccountMessageText
        let source = payload.item?.sourceContent.nonEmptyAccountMessageText
        let root = payload.item?.rootReplyContent.nonEmptyAccountMessageText
        let body = source ?? target ?? root ?? "查看回复"
        let contextLines = replyContextLines(body: body, target: target, root: root)
        let identifier = payload.id?.value ?? payload.replyTime?.value ?? 0
        return AccountMessageItem(
            id: "reply-\(identifier)-\(payload.replyTime?.value ?? 0)",
            serverID: payload.id?.value,
            category: .reply,
            actors: messageActor.map { [$0] } ?? [],
            count: max(1, count),
            title: title,
            body: body,
            contextLines: contextLines,
            timestamp: date(unixTime: payload.replyTime?.value),
            timestampText: nil,
            coverURLString: nil,
            link: AccountMessageLink(nativeURI: payload.item?.nativeURI),
            isLatest: false,
            noticeState: nil
        )
    }

    private static func mentionItem(_ payload: MentionItemPayload) -> AccountMessageItem {
        let messageActor = actor(payload.user)
        let actorName = messageActor?.name ?? "有人"
        let body = payload.item?.sourceContent.nonEmptyAccountMessageText ?? "查看提及内容"
        let identifier = payload.id?.value ?? payload.atTime?.value ?? 0
        return AccountMessageItem(
            id: "mention-\(identifier)-\(payload.atTime?.value ?? 0)",
            serverID: payload.id?.value,
            category: .mention,
            actors: messageActor.map { [$0] } ?? [],
            count: 1,
            title: "\(actorName) @ 了你",
            body: body,
            contextLines: [],
            timestamp: date(unixTime: payload.atTime?.value),
            timestampText: nil,
            coverURLString: normalizedImageURL(payload.item?.image),
            link: AccountMessageLink(nativeURI: payload.item?.nativeURI),
            isLatest: false,
            noticeState: nil
        )
    }

    private static func likeItem(_ payload: LikeItemPayload, isLatest: Bool) -> AccountMessageItem {
        let actors = (payload.users ?? []).compactMap(actor)
        let names = actors.map(\.name)
        let count = payload.counts?.value ?? names.count
        let leadingName = names.first ?? "有人"
        let title: String
        if count > max(names.count, 1) {
            title = "\(leadingName) 等 \(count) 人赞了你"
        } else if names.count > 1 {
            title = "\(names.joined(separator: "、")) 赞了你"
        } else {
            title = "\(leadingName) 赞了你"
        }
        let business = businessTitle(payload.item?.business)
        let body = business.isEmpty ? "赞了你的内容" : "赞了你的\(business)"
        let identifier = payload.id?.value ?? payload.likeTime?.value ?? 0
        return AccountMessageItem(
            id: "like-\(identifier)-\(payload.likeTime?.value ?? 0)",
            serverID: payload.id?.value,
            category: .like,
            actors: actors,
            count: max(1, count),
            title: title,
            body: body,
            contextLines: payload.item?.title.nonEmptyAccountMessageText.map { [$0] } ?? [],
            timestamp: date(unixTime: payload.likeTime?.value),
            timestampText: nil,
            coverURLString: normalizedImageURL(payload.item?.image),
            link: AccountMessageLink(nativeURI: payload.item?.nativeURI),
            isLatest: isLatest,
            noticeState: payload.noticeState?.value
        )
    }

    private static func systemItem(_ payload: SystemPayload) -> AccountMessageItem {
        let content = SystemContent(rawValue: payload.content)
        let identifier = payload.id?.value ?? payload.cursor?.value ?? 0
        return AccountMessageItem(
            id: "system-\(identifier)-\(payload.cursor?.value ?? 0)",
            serverID: payload.id?.value,
            category: .system,
            actors: [],
            count: 1,
            title: payload.title.nonEmptyAccountMessageText ?? "系统通知",
            body: content.text ?? "查看通知详情",
            contextLines: [],
            timestamp: date(timeText: payload.timeAt?.value),
            timestampText: payload.timeAt?.value.nonEmptyAccountMessageText,
            coverURLString: normalizedImageURL(content.imageURLString),
            link: AccountMessageLink(nativeURI: content.nativeURI, webURLString: content.webURLString),
            isLatest: false,
            noticeState: nil
        )
    }

    private static func actor(_ payload: ActorPayload?) -> AccountMessageActor? {
        guard let payload else { return nil }
        let name = payload.nickname.nonEmptyAccountMessageText ?? "用户"
        let avatarURLString = normalizedImageURL(payload.avatar)
        guard payload.mid?.value != nil || name != "用户" || avatarURLString != nil else { return nil }
        return AccountMessageActor(mid: payload.mid?.value, name: name, avatarURLString: avatarURLString)
    }

    private static func replyContextLines(
        body: String,
        target: String?,
        root: String?
    ) -> [String] {
        var seen = Set<String>()
        return [target, root].compactMap { value in
            guard let value,
                  value != body,
                  seen.insert(value).inserted
            else {
                return nil
            }
            return value
        }
    }

    private static func businessTitle(_ value: String?) -> String {
        switch value?.lowercased() {
        case "archive":
            return "视频"
        case "article":
            return "专栏"
        case "dynamic":
            return "动态"
        case "live":
            return "直播"
        case "music":
            return "音频"
        default:
            return ""
        }
    }

    private static func normalizedImageURL(_ value: String?) -> String? {
        value?.nonEmptyAccountMessageText?.normalizedBiliURL()
    }

    private static func date(unixTime: Int?) -> Date? {
        guard let unixTime, unixTime > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(unixTime))
    }

    private static func date(timeText: String?) -> Date? {
        guard let timeText = timeText.nonEmptyAccountMessageText else { return nil }
        if let seconds = TimeInterval(timeText), seconds > 0 {
            return Date(timeIntervalSince1970: seconds)
        }

        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: timeText) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: timeText) {
                return date
            }
        }
        return nil
    }

    private struct FlexibleInt: Decodable {
        let value: Int

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Int.self) {
                self.value = value
                return
            }
            if let value = try? container.decode(String.self), let integer = Int(value) {
                self.value = integer
                return
            }
            if let value = try? container.decode(Double.self) {
                self.value = Int(value)
                return
            }
            if let value = try? container.decode(Bool.self) {
                self.value = value ? 1 : 0
                return
            }
            throw DecodingError.typeMismatch(
                Int.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected an integer")
            )
        }
    }

    private struct FlexibleString: Decodable {
        let value: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self.value = value
                return
            }
            if let value = try? container.decode(Int.self) {
                self.value = String(value)
                return
            }
            if let value = try? container.decode(Double.self) {
                self.value = String(value)
                return
            }
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a string")
            )
        }
    }

    private struct CursorPayload: Decodable {
        let isEnd: Bool?
        let id: FlexibleInt?
        let time: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case isEnd = "is_end"
            case id, time
        }

        var messageCursor: AccountMessageCursor {
            AccountMessageCursor(id: id?.value, timestamp: time?.value, isEnd: isEnd ?? false)
        }
    }

    private struct UnreadPayload: Decodable {
        let at: FlexibleInt?
        let like: FlexibleInt?
        let reply: FlexibleInt?
        let system: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case at, like, reply
            case system = "sys_msg"
        }
    }

    private struct ActorPayload: Decodable {
        let mid: FlexibleInt?
        let nickname: String?
        let avatar: String?
    }

    private struct ReplyContentPayload: Decodable {
        let business: String?
        let nativeURI: String?
        let rootReplyContent: String?
        let sourceContent: String?
        let targetReplyContent: String?

        enum CodingKeys: String, CodingKey {
            case business
            case nativeURI = "native_uri"
            case rootReplyContent = "root_reply_content"
            case sourceContent = "source_content"
            case targetReplyContent = "target_reply_content"
        }
    }

    private struct ReplyItemPayload: Decodable {
        let id: FlexibleInt?
        let user: ActorPayload?
        let item: ReplyContentPayload?
        let counts: FlexibleInt?
        let isMulti: FlexibleInt?
        let replyTime: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case id, user, item, counts
            case isMulti = "is_multi"
            case replyTime = "reply_time"
        }
    }

    private struct ReplyPayload: Decodable {
        let cursor: CursorPayload?
        let items: [ReplyItemPayload]?
        let lastViewAt: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case cursor, items
            case lastViewAt = "last_view_at"
        }
    }

    private struct MentionContentPayload: Decodable {
        let business: String?
        let image: String?
        let sourceContent: String?
        let nativeURI: String?

        enum CodingKeys: String, CodingKey {
            case business, image
            case sourceContent = "source_content"
            case nativeURI = "native_uri"
        }
    }

    private struct MentionItemPayload: Decodable {
        let id: FlexibleInt?
        let user: ActorPayload?
        let item: MentionContentPayload?
        let atTime: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case id, user, item
            case atTime = "at_time"
        }
    }

    private struct MentionPayload: Decodable {
        let cursor: CursorPayload?
        let items: [MentionItemPayload]?
        let lastViewAt: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case cursor, items
            case lastViewAt = "last_view_at"
        }
    }

    private struct LikeContentPayload: Decodable {
        let business: String?
        let title: String?
        let image: String?
        let nativeURI: String?

        enum CodingKeys: String, CodingKey {
            case business, title, image
            case nativeURI = "native_uri"
        }
    }

    private struct LikeItemPayload: Decodable {
        let id: FlexibleInt?
        let users: [ActorPayload]?
        let item: LikeContentPayload?
        let counts: FlexibleInt?
        let likeTime: FlexibleInt?
        let noticeState: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case id, users, item, counts
            case likeTime = "like_time"
            case noticeState = "notice_state"
        }
    }

    private struct LikeBucketPayload: Decodable {
        let cursor: CursorPayload?
        let items: [LikeItemPayload]?
        let lastViewAt: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case cursor, items
            case lastViewAt = "last_view_at"
        }
    }

    private struct LikePayload: Decodable {
        let latest: LikeBucketPayload?
        let total: LikeBucketPayload?
    }

    private struct LikeDetailPayload: Decodable {
        let page: LikeDetailPagePayload?
        let card: LikeDetailCardPayload?
        let items: [LikeDetailItemPayload]?
    }

    private struct LikeDetailPagePayload: Decodable {
        let isEnd: Bool?

        enum CodingKeys: String, CodingKey {
            case isEnd = "is_end"
        }
    }

    private struct LikeDetailCardPayload: Decodable {
        let title: String?
    }

    private struct LikeDetailItemPayload: Decodable {
        let user: ActorPayload?
        let likeTime: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case user
            case likeTime = "like_time"
        }
    }

    private struct FollowersPayload: Decodable {
        let list: [FollowerPayload]?
        let total: FlexibleInt?
    }

    private struct FollowerPayload: Decodable {
        let mid: FlexibleInt?
        let uname: String?
        let face: String?
        let sign: String?
        let mtime: FlexibleInt?
    }

    private struct PrivateSessionListPayload: Decodable {
        let sessionList: [PrivateSessionPayload]?

        enum CodingKeys: String, CodingKey {
            case sessionList = "session_list"
        }
    }

    private struct AccountMessageEmotePanelPayload: Decodable {
        let packages: [AccountMessageEmotePackagePayload]?
    }

    private struct AccountMessageEmotePackagePayload: Decodable {
        let emotes: [AccountMessageEmotePayload]?

        enum CodingKeys: String, CodingKey {
            case emotes = "emote"
        }
    }

    private struct AccountMessageEmotePayload: Decodable {
        let text: String?
        let url: String?
    }

    private struct PrivateSessionPayload: Decodable {
        let talkerID: FlexibleInt?
        let topTimestamp: FlexibleInt?
        let isDND: FlexibleInt?
        let sessionTimestamp: FlexibleInt?
        let unreadCount: FlexibleInt?
        let lastMessage: PrivateMessagePayload?
        let accountInfo: PrivateSessionAccountPayload?

        enum CodingKeys: String, CodingKey {
            case talkerID = "talker_id"
            case topTimestamp = "top_ts"
            case isDND = "is_dnd"
            case sessionTimestamp = "session_ts"
            case unreadCount = "unread_count"
            case lastMessage = "last_msg"
            case accountInfo = "account_info"
        }
    }

    private struct PrivateSessionAccountPayload: Decodable {
        let name: String?
        let picURL: String?

        enum CodingKeys: String, CodingKey {
            case name
            case picURL = "pic_url"
        }
    }

    private struct PrivateMessagePagePayload: Decodable {
        let messages: [PrivateMessagePayload]?
        let hasMore: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case messages
            case hasMore = "has_more"
        }
    }

    private struct PrivateMessagePayload: Decodable {
        let senderUID: FlexibleInt?
        let receiverID: FlexibleInt?
        let msgType: FlexibleInt?
        let msgStatus: FlexibleInt?
        let messageKey: FlexibleInt?
        let content: String?
        let sequence: FlexibleInt?
        let timestamp: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case senderUID = "sender_uid"
            case receiverID = "receiver_id"
            case msgType = "msg_type"
            case msgStatus = "msg_status"
            case messageKey = "msg_key"
            case content
            case sequence = "msg_seqno"
            case timestamp
        }
    }

    private struct PrivateImageUploadPayload: Decodable {
        let imageURL: String?
        let imageWidth: Int?
        let imageHeight: Int?
        let imageSize: Double?

        enum CodingKeys: String, CodingKey {
            case imageURL = "image_url"
            case imageWidth = "image_width"
            case imageHeight = "image_height"
            case imageSize = "img_size"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
            imageWidth = Self.decodeInt(in: container, forKey: .imageWidth)
            imageHeight = Self.decodeInt(in: container, forKey: .imageHeight)
            if let value = try? container.decode(Double.self, forKey: .imageSize) {
                imageSize = value
            } else if let value = try? container.decode(Int.self, forKey: .imageSize) {
                imageSize = Double(value)
            } else if let value = try? container.decode(String.self, forKey: .imageSize) {
                imageSize = Double(value)
            } else {
                imageSize = nil
            }
        }

        private static func decodeInt(
            in container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> Int? {
            if let value = try? container.decode(Int.self, forKey: key) {
                return value
            }
            if let value = try? container.decode(String.self, forKey: key) {
                return Int(value)
            }
            if let value = try? container.decode(Double.self, forKey: key) {
                return Int(value)
            }
            return nil
        }
    }

    private struct SystemPayload: Decodable {
        let id: FlexibleInt?
        let cursor: FlexibleInt?
        let title: String?
        let content: String?
        let timeAt: FlexibleString?

        enum CodingKeys: String, CodingKey {
            case id, cursor, title, content
            case timeAt = "time_at"
        }
    }

    private struct AcknowledgementPayload: Decodable {}

    private struct SystemContent {
        let text: String?
        let webURLString: String?
        let nativeURI: String?
        let imageURLString: String?

        init(rawValue: String?) {
            let rawText = rawValue.nonEmptyAccountMessageText
            guard let rawText,
                  let data = rawText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                text = rawText
                webURLString = nil
                nativeURI = nil
                imageURLString = nil
                return
            }

            let web = object["web"] as? String
            let url = object["url"] as? String
            let native = (object["native_uri"] as? String)
                ?? (object["nativeUri"] as? String)
                ?? (url?.hasPrefix("bilibili://") == true ? url : nil)
            let content = (object["content"] as? String)
                ?? (object["text"] as? String)
                ?? (object["desc"] as? String)
            let image = (object["image"] as? String) ?? (object["pic"] as? String)
            text = content.nonEmptyAccountMessageText
                ?? (web?.looksLikeHTTPURL == true ? nil : web?.nonEmptyAccountMessageText)
                ?? rawText
            webURLString = (web?.looksLikeHTTPURL == true ? web : url).nonEmptyAccountMessageText
            nativeURI = native.nonEmptyAccountMessageText
            imageURLString = image.nonEmptyAccountMessageText
        }
    }

    private struct PrivateMessageContent {
        let text: String
        let imageURLString: String?
        let routeURL: URL?

        init(rawValue: String?, type: Int?) {
            let rawText = rawValue.nonEmptyAccountMessageText
            guard let rawText,
                  let data = rawText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                text = rawText ?? "[消息]"
                imageURLString = nil
                routeURL = nil
                return
            }

            let firstSubcard = (object["sub_cards"] as? [[String: Any]])?.first
            let title = Self.firstString(
                in: object,
                keys: ["content", "text", "title", "main_title", "summary"]
            )
            let image = Self.firstString(
                in: object,
                keys: ["image_url", "cover_url", "cover", "thumb", "pic_url"]
            )
                ?? Self.firstArrayString(in: object, key: "image_urls")
                ?? Self.firstString(in: firstSubcard, keys: ["cover_url", "cover"])
                ?? ((type == 2 || type == 6) ? Self.firstString(in: object, keys: ["url"]) : nil)
            let directDestination = Self.firstString(
                in: object,
                keys: ["jump_url", "jumpUrl", "jump_uri", "uri"]
            )
                ?? ((type == 2 || type == 6) ? nil : Self.firstString(in: object, keys: ["url"]))
            let destination = directDestination
                ?? Self.inferredDestination(in: object, type: type, firstSubcard: firstSubcard)

            switch type {
            case 1:
                text = title ?? "[文字消息]"
                imageURLString = nil
            case 2, 6:
                text = title ?? "[图片]"
                imageURLString = image
            case 5:
                text = "[消息已撤回]"
                imageURLString = nil
            case 7:
                text = Self.joinedText([
                    title,
                    Self.firstString(in: object, keys: ["headline"]),
                    Self.firstString(in: object, keys: ["author"])
                ]) ?? "[分享]"
                imageURLString = image
            case 10:
                text = Self.joinedText([
                    Self.firstString(in: object, keys: ["title"]),
                    Self.firstString(in: object, keys: ["text", "content"])
                ]) ?? "[通知]"
                imageURLString = image
            case 11:
                text = Self.firstString(in: object, keys: ["title"]) ?? "[视频]"
                imageURLString = image
            case 12:
                text = Self.joinedText([
                    Self.firstString(in: object, keys: ["title"]),
                    Self.firstString(in: object, keys: ["summary"])
                ]) ?? "[专栏]"
                imageURLString = image
            case 13:
                text = title ?? "[图片卡片]"
                imageURLString = image
            case 14:
                let author = Self.firstString(in: object, keys: ["author"])
                let source = Self.firstValueString(in: object, keys: ["source"])
                text = Self.joinedText([
                    Self.firstString(in: object, keys: ["title"]),
                    Self.joinedText([author, source], separator: " · ")
                ]) ?? "[分享卡片]"
                imageURLString = image
            case 16:
                text = Self.joinedText([
                    Self.firstString(in: object, keys: ["main_title"]),
                    Self.firstString(in: firstSubcard, keys: ["field1"])
                ]) ?? "[视频合集]"
                imageURLString = image
            case 18:
                text = Self.tipText(in: object) ?? title ?? "[提示消息]"
                imageURLString = nil
            default:
                text = title ?? "[消息]"
                imageURLString = image
            }
            routeURL = destination.flatMap {
                AccountMessageLinkResolver.resolve(nativeURI: $0, webURLString: $0)
            }
        }

        private static func firstString(in object: [String: Any]?, keys: [String]) -> String? {
            guard let object else { return nil }
            return keys.lazy.compactMap { key in
                (object[key] as? String)?.nonEmptyAccountMessageText
            }.first
        }

        private static func firstValueString(in object: [String: Any], keys: [String]) -> String? {
            keys.lazy.compactMap { key -> String? in
                switch object[key] {
                case let value as String:
                    return value.nonEmptyAccountMessageText
                case let value as NSNumber:
                    return value.stringValue
                default:
                    return nil
                }
            }.first
        }

        private static func firstArrayString(in object: [String: Any], key: String) -> String? {
            (object[key] as? [Any])?.lazy.compactMap {
                ($0 as? String)?.nonEmptyAccountMessageText
            }.first
        }

        private static func inferredDestination(
            in object: [String: Any],
            type: Int?,
            firstSubcard: [String: Any]?
        ) -> String? {
            switch type {
            case 7:
                let source = Int(firstValueString(in: object, keys: ["source"]) ?? "")
                let id = firstValueString(in: object, keys: ["id"])
                switch source {
                case 2, 11:
                    return id.map { "https://t.bilibili.com/\($0)" }
                case 5:
                    return videoDestination(in: object, fallbackID: id)
                case 6:
                    return id.map { "https://www.bilibili.com/read/\($0.hasPrefix("cv") ? $0 : "cv\($0)")" }
                case 16:
                    return id.map { "https://www.bilibili.com/bangumi/play/\($0.hasPrefix("ep") ? $0 : "ep\($0)")" }
                default:
                    return nil
                }
            case 11:
                return videoDestination(in: object, fallbackID: firstValueString(in: object, keys: ["aid", "id"]))
            case 12:
                return firstValueString(in: object, keys: ["rid", "id"]).map {
                    "https://www.bilibili.com/read/\($0.hasPrefix("cv") ? $0 : "cv\($0)")"
                }
            case 14:
                guard firstString(in: object, keys: ["source"]) == "直播",
                      let roomID = firstValueString(in: object, keys: ["sourceID", "source_id", "id"])
                else {
                    return nil
                }
                return "https://live.bilibili.com/\(roomID)"
            case 16:
                return firstString(in: firstSubcard, keys: ["jump_url", "jumpUrl", "uri"])
            default:
                return nil
            }
        }

        private static func videoDestination(in object: [String: Any], fallbackID: String?) -> String? {
            if let bvid = firstValueString(in: object, keys: ["bvid"]), !bvid.isEmpty {
                return "https://www.bilibili.com/video/\(bvid)"
            }
            return fallbackID.map {
                "https://www.bilibili.com/video/\($0.hasPrefix("av") ? $0 : "av\($0)")"
            }
        }

        private static func joinedText(_ values: [String?], separator: String = "\n") -> String? {
            var seen = Set<String>()
            let values = values.compactMap { value -> String? in
                guard let value = value?.nonEmptyAccountMessageText,
                      seen.insert(value).inserted
                else {
                    return nil
                }
                return value
            }
            return values.isEmpty ? nil : values.joined(separator: separator)
        }

        private static func tipText(in object: [String: Any]) -> String? {
            let content: [[String: Any]]?
            if let values = object["content"] as? [[String: Any]] {
                content = values
            } else if let rawValue = object["content"] as? String,
                      let data = rawValue.data(using: .utf8) {
                content = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
            } else {
                content = nil
            }
            guard let content else { return nil }
            let values = content.compactMap { ($0["text"] as? String)?.nonEmptyAccountMessageText }
            return values.isEmpty ? nil : values.joined(separator: "\n")
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value.nonEmptyAccountMessageText
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }
}

private extension Optional where Wrapped == String {
    nonisolated var nonEmptyAccountMessageText: String? {
        self?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyAccountMessageText
    }
}

private extension String {
    nonisolated var looksLikeHTTPURL: Bool {
        let lowercased = lowercased()
        return lowercased.hasPrefix("https://") || lowercased.hasPrefix("http://")
    }
}
