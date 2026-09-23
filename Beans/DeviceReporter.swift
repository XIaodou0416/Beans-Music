import Foundation
import UIKit

struct FeedbackSubmissionResult: Sendable {
    let downloadUnlocked: Bool
    let feedbackID: String
    let submittedAt: String?
}

struct BeansDeveloperAnnouncement: Decodable, Equatable, Sendable {
    let announcement: String
    let enabled: Bool
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case announcement
        case enabled = "announcement_enabled"
        case updatedAt = "updated_at"
    }
}

struct BeansDownloadAccessRecord: Decodable, Identifiable, Equatable {
    let userID: String
    let publicUserID: String?
    let deviceModel: String
    let deviceName: String
    let systemName: String
    let systemVersion: String
    let appVersion: String
    let appBuild: String
    let lastSeenAt: String
    let enabled: Bool
    let changedAt: String

    var id: String { "\(userID)-\(changedAt)-\(enabled)" }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case publicUserID = "public_user_id"
        case deviceModel = "device_model"
        case deviceName = "device_name"
        case systemName = "system_name"
        case systemVersion = "system_version"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case lastSeenAt = "last_seen_at"
        case enabled
        case changedAt = "changed_at"
    }
}

struct BeansExclusiveAccessRecord: Decodable, Identifiable, Equatable {
    let userID: String
    let publicUserID: String?
    let deviceModel: String
    let deviceName: String
    let systemName: String
    let systemVersion: String
    let appVersion: String
    let appBuild: String
    let lastSeenAt: String
    let enabled: Bool
    let badgeStyle: BeansExclusiveIDBadgeStyle?
    let changedAt: String

    var id: String { "exclusive-\(userID)-\(changedAt)-\(enabled)" }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case publicUserID = "public_user_id"
        case deviceModel = "device_model"
        case deviceName = "device_name"
        case systemName = "system_name"
        case systemVersion = "system_version"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case lastSeenAt = "last_seen_at"
        case enabled
        case badgeStyle = "exclusive_badge_style"
        case changedAt = "changed_at"
    }
}

enum BeansExclusiveIDBadgeStyle: String, CaseIterable, Codable {
    case blackPurpleGold = "black_purple_gold"
    case classicGold = "classic_gold"

    var displayName: String {
        switch self {
        case .blackPurpleGold: return "黑紫金"
        case .classicGold: return "经典金色"
        }
    }
}

enum BeansBackendSettings {
    static let downloadUnlockKey = "beans.downloadFeatureUnlocked"
    static let downloadGlobalUnlockKey = "beans.downloadGlobalFeatureEnabled"
    static let blockedKey = "beans.backend.userBlocked"
    static let exclusiveIDKey = "beans.backend.exclusiveID"
    static let exclusiveIDBadgeStyleKey = "beans.backend.exclusiveIDBadgeStyle"
    static let publicIDRevisionKey = "beans.backend.publicIDRevision"
}

/// 启动时向后台上报基础设备信息；IP 由后台从请求中获取。
@MainActor
final class DeviceReporter {
    static let shared = DeviceReporter()

    private var reported = false
    private var heartbeatTask: Task<Void, Never>?
    private var heartbeatInFlight = false
    private let apiEndpoint = URL(string: "http://189.24.78.193/beans")!
    private let legacyHeartbeatEndpoint = URL(string: "http://189.24.78.193/beans/heartbeat")!

    private init() {}

    deinit {
        heartbeatTask?.cancel()
    }

    func reportLaunch() async {
        guard !reported else { return }
        reported = true
        defer { startHeartbeatLoop() }
        var payload = devicePayload()
        payload["event"] = "register"
        let publicIDRevision = UserDefaults.standard.integer(forKey: BeansBackendSettings.publicIDRevisionKey)

        do {
            let data = try await postJSON(to: endpoint(for: "register"), payload: payload)
            applyServerState(from: data, allowPublicIDUpdate: true, expectedPublicIDRevision: publicIDRevision)
        } catch {
            // 保留已有心跳接口作为兼容兜底；新后端部署前不影响原有启动上报。
            do {
                let data = try await postJSON(to: legacyHeartbeatEndpoint, payload: payload)
                applyServerState(from: data, allowPublicIDUpdate: true, expectedPublicIDRevision: publicIDRevision)
            } catch {
                BeansLogger.shared.log("设备启动信息上报失败：\(error.localizedDescription)", level: .debug)
            }
        }
    }

    /// 运行期间定时上报最后活跃时间，后台据此判断在线状态并实时刷新拉黑状态。
    func reportHeartbeat() async {
        guard !heartbeatInFlight else { return }
        heartbeatInFlight = true
        defer { heartbeatInFlight = false }
        let publicIDRevision = UserDefaults.standard.integer(forKey: BeansBackendSettings.publicIDRevisionKey)
        do {
            let data = try await postJSON(to: endpoint(for: "heartbeat"), payload: devicePayload())
            applyServerState(from: data, allowPublicIDUpdate: true, expectedPublicIDRevision: publicIDRevision)
        } catch {
            BeansLogger.shared.log("在线心跳上报失败：\(error.localizedDescription)", level: .debug)
        }
    }

    private func startHeartbeatLoop() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.reportHeartbeat()
            }
        }
    }

    func submitFeedback(
        phoneModel: String,
        phoneSystem: String,
        problem: String,
        attachmentURLs: [URL]
    ) async throws -> FeedbackSubmissionResult {
        let normalizedModel = phoneModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSystem = phoneSystem.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProblem = problem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty, !normalizedSystem.isEmpty, !normalizedProblem.isEmpty else {
            throw BackendRequestError.missingRequiredFields
        }

        var fields = devicePayload()
        fields["phone_model"] = normalizedModel
        fields["phone_system"] = normalizedSystem
        fields["problem"] = normalizedProblem

        let data = try await postMultipart(
            to: endpoint(for: "feedback"),
            fields: fields,
            attachmentURLs: attachmentURLs
        )
        let response = try decodeResponse(data)
        guard response.ok != false else {
            throw BackendRequestError.server(response.message ?? "提交失败")
        }
        applyServerState(response)
        return FeedbackSubmissionResult(
            downloadUnlocked: response.downloadUnlocked == true,
            feedbackID: response.feedbackID ?? UUID().uuidString,
            submittedAt: response.submittedAt
        )
    }

    func fetchFeedbackHistory() async throws -> [FeedbackServerRecord] {
        guard var components = URLComponents(
            url: endpoint(for: "feedback").appendingPathComponent("mine"),
            resolvingAgainstBaseURL: false
        ) else {
            throw BackendRequestError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "user_id", value: DeviceIdentity.userID)
        ]
        guard let url = components.url else {
            throw BackendRequestError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, body: data)
        let result = try JSONDecoder().decode(FeedbackListResponse.self, from: data)
        guard result.ok != false else {
            throw BackendRequestError.server(result.message ?? "获取反馈记录失败")
        }
        return result.feedback
    }

    func deleteMyFeedback(feedbackID: String) async throws {
        let url = endpoint(for: "feedback")
            .appendingPathComponent("mine")
            .appendingPathComponent(feedbackID)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(DeviceIdentity.userID, forHTTPHeaderField: "X-Beans-User-ID")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": DeviceIdentity.userID
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let result = try decodeResponse(data)
        guard result.ok != false else {
            throw BackendRequestError.server(result.message ?? "删除反馈失败")
        }
    }

    func backendURL(for rawValue: String) -> URL? {
        if let absoluteURL = URL(string: rawValue), absoluteURL.scheme != nil {
            return absoluteURL
        }
        let root = apiEndpoint.deletingLastPathComponent()
        return URL(string: rawValue, relativeTo: root)?.absoluteURL
    }

    private func endpoint(for action: String) -> URL {
        apiEndpoint.appendingPathComponent(action)
    }

    private func devicePayload() -> [String: String] {
        let device = UIDevice.current
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return [
            "user_id": DeviceIdentity.userID,
            "public_user_id": DeviceIdentity.publicID,
            "model": DeviceIdentity.hardwareModel,
            "device_name": device.model,
            "system": "\(device.systemName) \(device.systemVersion)",
            "system_version": device.systemVersion,
            "app_version": UpdateChecker.currentVersion,
            "app_build": build,
            "listening_seconds": String(Int(PlayerManager.storedListeningDuration.rounded(.down))),
            "listening_play_count": String(PlayerManager.storedPlayCount)
        ]
    }

    private func postJSON(to url: URL, payload: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return data
    }

    private func postMultipart(
        to url: URL,
        fields: [String: String],
        attachmentURLs: [URL]
    ) async throws -> Data {
        let boundary = "BeansFeedback-\(UUID().uuidString)"
        var body = Data()

        for (name, value) in fields {
            body.appendMultipartField(name: name, value: value, boundary: boundary)
        }

        for (index, url) in attachmentURLs.enumerated() {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size <= 50 * 1024 * 1024 else {
                throw BackendRequestError.attachmentTooLarge
            }
            let data = try Data(contentsOf: url)
            let contentType = DeviceIdentity.mimeType(for: url)
            let filename = url.lastPathComponent.isEmpty ? "attachment-\(index)" : url.lastPathComponent
            body.appendMultipartFile(
                name: "attachments[]",
                filename: filename,
                contentType: contentType,
                data: data,
                boundary: boundary
            )
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, body: data)
        return data
    }

    private func validate(_ response: URLResponse, body: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            throw BackendRequestError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if let body, let message = backendMessage(from: body) {
                throw BackendRequestError.server(message)
            }
            if http.statusCode == 404 {
                throw BackendRequestError.server(beansLocalized(
                    "服务器尚未部署下载授权接口，请先更新后台服务。",
                    "The server has not deployed the download-access endpoint yet. Update the backend first."
                ))
            }
            throw BackendRequestError.httpStatus(http.statusCode)
        }
    }

    func grantDownloadAccess(to targetUserID: String, enabled: Bool) async throws {
        guard BeansDeveloperAccess.isAuthorized else {
            throw BackendRequestError.server("当前设备没有开发者权限")
        }
        let normalizedTarget = targetUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTarget.range(of: #"^[a-f0-9-]{16,80}$"#, options: .regularExpression) != nil else {
            throw BackendRequestError.server("设备码格式不正确")
        }

        var request = URLRequest(url: endpoint(for: "developer/grant-download"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "developer_user_id": DeviceIdentity.userID,
            "developer_public_user_id": DeviceIdentity.publicID,
            "target_user_id": normalizedTarget,
            "target_public_user_id": "",
            "download_unlocked": enabled
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response, body: data)
            let result = try decodeResponse(data)
            guard result.ok != false else {
                throw BackendRequestError.server(result.message ?? "下载权限操作失败")
            }
            applyServerState(
                result,
                allowPublicIDUpdate: normalizedTarget.lowercased() == DeviceIdentity.userID.lowercased()
            )
        } catch {
            // The backend writes the permission before its response reaches the
            // device. Confirm the resulting state before showing a failure;
            // otherwise a slow or dropped response looks like a failed action
            // even though authorization or revocation already succeeded.
            if isRecoverableGrantError(error),
               await serverConfirmsDownloadAccess(target: normalizedTarget, enabled: enabled) {
                BeansLogger.shared.log("下载权限请求未收到完整响应，但后台状态已确认，按成功处理", level: .debug)
                return
            }
            throw error
        }
    }

    func fetchGlobalDownloadAccess() async throws -> Bool {
        guard BeansDeveloperAccess.isAuthorized else {
            throw BackendRequestError.server("当前设备没有开发者权限")
        }
        guard var components = URLComponents(
            url: endpoint(for: "developer/download-global"),
            resolvingAgainstBaseURL: false
        ) else {
            throw BackendRequestError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "developer_user_id", value: DeviceIdentity.userID)]
        guard let url = components.url else { throw BackendRequestError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, body: data)
        let result = try JSONDecoder().decode(BeansGlobalDownloadResponse.self, from: data)
        guard result.ok != false else {
            throw BackendRequestError.server(result.message ?? "获取全局下载状态失败")
        }
        UserDefaults.standard.set(result.enabled, forKey: BeansBackendSettings.downloadGlobalUnlockKey)
        return result.enabled
    }

    func setGlobalDownloadAccess(_ enabled: Bool) async throws -> Bool {
        guard BeansDeveloperAccess.isAuthorized else {
            throw BackendRequestError.server("当前设备没有开发者权限")
        }
        var request = URLRequest(url: endpoint(for: "developer/download-global"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "developer_user_id": DeviceIdentity.userID,
            "developer_public_user_id": DeviceIdentity.publicID,
            "enabled": enabled
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, body: data)
        let result = try JSONDecoder().decode(BeansGlobalDownloadResponse.self, from: data)
        guard result.ok != false else {
            throw BackendRequestError.server(result.message ?? "保存全局下载状态失败")
        }
        UserDefaults.standard.set(result.enabled, forKey: BeansBackendSettings.downloadGlobalUnlockKey)
        return result.enabled
    }

    func fetchDeveloperAnnouncement() async throws -> BeansDeveloperAnnouncement {
        guard BeansDeveloperAccess.isAuthorized else {
            throw BackendRequestError.server("当前设备没有开发者权限")
        }
        guard var components = URLComponents(
            url: endpoint(for: "developer/announcement"),
            resolvingAgainstBaseURL: false
        ) else {
            throw BackendRequestError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "developer_user_id", value: DeviceIdentity.userID)]
        guard let url = components.url else { throw BackendRequestError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, body: data)
        let result = try JSONDecoder().decode(BeansDeveloperAnnouncementResponse.self, from: data)
        guard result.ok != false else {
            throw BackendRequestError.server(result.message ?? "获取公告失败")
        }
        return result.announcement
    }

    func updateDeveloperAnnouncement(enabled: Bool, text: String) async throws -> BeansDeveloperAnnouncement {
        guard BeansDeveloperAccess.isAuthorized else {
            throw BackendRequestError.server("当前设备没有开发者权限")
        }
        let normalizedText = String(text.prefix(8000))
        let data = try await postJSON(
            to: endpoint(for: "developer/announcement"),
            payload: [
                "developer_user_id": DeviceIdentity.userID,
                "announcement_enabled": enabled ? "true" : "false",
                "announcement": normalizedText,
            ]
        )
        let result = try JSONDecoder().decode(BeansDeveloperAnnouncementResponse.self, from: data)
        guard result.ok != false else {
            throw BackendRequestError.server(result.message ?? "保存公告失败")
        }
        return result.announcement
    }

    func grantExclusiveID(
        to targetUserID: String,
        assignedPublicID: String,
        enabled: Bool,
        badgeStyle: BeansExclusiveIDBadgeStyle
    ) async throws {
        guard BeansDeveloperAccess.isAuthorized else {
            throw BackendRequestError.server("当前设备没有开发者权限")
        }
        let normalizedTarget = targetUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedAssignedID = assignedPublicID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTarget.range(of: #"^[a-f0-9-]{16,80}$"#, options: .regularExpression) != nil else {
            throw BackendRequestError.server("设备码格式不正确")
        }
        guard normalizedAssignedID.isEmpty
            || DeviceIdentity.isValidPublicID(normalizedAssignedID) else {
            throw BackendRequestError.server("用户 ID 最多 24 个字符，不能包含空格")
        }

        var request = URLRequest(url: endpoint(for: "developer/grant-exclusive-id"))
        request.httpMethod = "POST"
        // Permission changes are small writes. Do not leave the developer UI
        // spinning behind a long transport timeout when the server has already
        // committed the change but its response was dropped.
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "developer_user_id": DeviceIdentity.userID,
            "developer_public_user_id": DeviceIdentity.publicID,
            "target_user_id": normalizedTarget,
            "target_public_user_id": "",
            "assigned_public_user_id": normalizedAssignedID,
            "exclusive_id": enabled,
            "exclusive_badge_style": badgeStyle.rawValue
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response, body: data)
            let result = try decodeResponse(data)
            guard result.ok != false else {
                throw BackendRequestError.server(result.message ?? "专属 ID 操作失败")
            }
            guard normalizedAssignedID.isEmpty || result.publicUserID == normalizedAssignedID else {
                throw BackendRequestError.invalidResponse
            }
            // This response describes the target device, not the developer.
            if normalizedTarget == DeviceIdentity.userID.lowercased() {
                applyServerState(result, allowPublicIDUpdate: true)
            }
        } catch {
            if isRecoverableGrantError(error),
               await serverConfirmsExclusiveAccess(
                   target: normalizedTarget,
                   enabled: enabled,
                   assignedPublicID: normalizedAssignedID,
                   badgeStyle: badgeStyle
               ) {
                BeansLogger.shared.log("专属 ID 请求未收到完整响应，但后台状态已确认，按成功处理", level: .debug)
                if normalizedTarget.lowercased() == DeviceIdentity.userID.lowercased() {
                    await reportHeartbeat()
                }
                return
            }
            throw error
        }
    }

    private func isRecoverableGrantError(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let backendError = error as? BackendRequestError,
           case .invalidResponse = backendError {
            return true
        }
        return false
    }

    private func serverConfirmsDownloadAccess(target: String, enabled: Bool) async -> Bool {
        let normalizedTarget = target.lowercased()
        for attempt in 0..<3 {
            if let records = try? await fetchDownloadAccessRecords(),
               let record = records.first(where: { record in
                   record.userID.lowercased() == normalizedTarget
                       || record.publicUserID?.lowercased() == normalizedTarget
               }),
               record.enabled == enabled {
                return true
            }

            if attempt < 2 {
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 250_000_000)
            }
        }
        return false
    }

    private func serverConfirmsExclusiveAccess(
        target: String,
        enabled: Bool,
        assignedPublicID: String,
        badgeStyle: BeansExclusiveIDBadgeStyle
    ) async -> Bool {
        let normalizedTarget = target.lowercased()
        let expectedPublicID = assignedPublicID.trimmingCharacters(in: .whitespacesAndNewlines)
        for attempt in 0..<3 {
            if let record = try? await fetchExclusiveAccessStatus(for: normalizedTarget),
               record.enabled == enabled,
               record.badgeStyle == nil || record.badgeStyle == badgeStyle,
               expectedPublicID.isEmpty || record.publicUserID == expectedPublicID {
                return true
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 300_000_000)
            }
        }
        return false
    }

    private func fetchExclusiveAccessStatus(for target: String) async throws -> BeansExclusiveAccessRecord {
        guard var components = URLComponents(
            url: endpoint(for: "developer/exclusive-access/status"),
            resolvingAgainstBaseURL: false
        ) else {
            throw BackendRequestError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "developer_user_id", value: DeviceIdentity.userID),
            URLQueryItem(name: "target_user_id", value: target),
            URLQueryItem(name: "target_public_user_id", value: "")
        ]
        guard let url = components.url else { throw BackendRequestError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, body: data)
        let result = try JSONDecoder().decode(BeansExclusiveAccessStatusResponse.self, from: data)
        guard result.ok != false, let record = result.record else {
            throw BackendRequestError.server(result.message ?? "未找到专属 ID 记录")
        }
        return record
    }

    func fetchDownloadAccessRecords() async throws -> [BeansDownloadAccessRecord] {
        guard BeansDeveloperAccess.isAuthorized else {
            throw BackendRequestError.server("当前设备没有开发者权限")
        }
        guard var components = URLComponents(
            url: endpoint(for: "developer/download-access"),
            resolvingAgainstBaseURL: false
        ) else {
            throw BackendRequestError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "developer_user_id", value: DeviceIdentity.userID)
        ]
        guard let url = components.url else {
            throw BackendRequestError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, body: data)
        let result = try JSONDecoder().decode(BeansDownloadAccessResponse.self, from: data)
        guard result.ok != false else {
            throw BackendRequestError.server(result.message ?? "获取下载权限记录失败")
        }
        return result.records
    }

    func fetchExclusiveAccessRecords() async throws -> [BeansExclusiveAccessRecord] {
        guard BeansDeveloperAccess.isAuthorized else {
            throw BackendRequestError.server("当前设备没有开发者权限")
        }
        guard var components = URLComponents(
            url: endpoint(for: "developer/exclusive-access"),
            resolvingAgainstBaseURL: false
        ) else {
            throw BackendRequestError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "developer_user_id", value: DeviceIdentity.userID)
        ]
        guard let url = components.url else {
            throw BackendRequestError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, body: data)
        let result = try JSONDecoder().decode(BeansExclusiveAccessResponse.self, from: data)
        guard result.ok != false else {
            throw BackendRequestError.server(result.message ?? "获取专属 ID 记录失败")
        }
        return result.records
    }

    private func backendMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawMessage = object["message"] as? String,
              !rawMessage.isEmpty else {
            return nil
        }

        switch rawMessage {
        case "unsupported_attachment":
            return beansLocalized("不支持这个文件类型，请选择 JS、图片、视频或普通文件。", "This file type is not supported. Choose a JS file, image, video, or regular file.")
        case "attachment_upload_failed":
            return beansLocalized("附件上传失败，文件可能过大或数量超出限制。", "The attachment upload failed. The files may be too large or exceed the limit.")
        case "attachment_too_large":
            return beansLocalized("单个附件不能超过 50 MB。", "Each attachment must be 50 MB or smaller.")
        case "too_many_attachments":
            return beansLocalized("最多只能上传 4 个附件。", "You can upload up to four attachments.")
        case "missing_required_fields":
            return beansLocalized("请填写全部必填项。", "Please complete all required fields.")
        case "invalid_user_id":
            return beansLocalized("设备标识无效，请重启应用后重试。", "The device identifier is invalid. Restart the app and try again.")
        case "developer_unauthorized":
            return beansLocalized("当前设备没有开发者权限。", "This device does not have developer access.")
        case "invalid_public_user_id":
            return beansLocalized("用户 ID 最多 24 个字符，不能包含空格。", "The public ID can contain up to 24 non-space characters.")
        case "public_user_id_taken":
            return beansLocalized("这个用户 ID 已被其他设备使用。", "That public ID is already assigned to another device.")
        case "user_not_found":
            return beansLocalized("没有找到这个设备，请确认对方已经启动过软件。", "That device was not found. Ask the user to launch the app first.")
        case "server_error":
            return beansLocalized("服务器处理失败，请稍后重试。", "The server could not process the request. Please try again later.")
        default:
            return rawMessage
        }
    }

    private func applyServerState(
        from data: Data,
        allowPublicIDUpdate: Bool = false,
        expectedPublicIDRevision: Int? = nil
    ) {
        guard let response = try? decodeResponse(data) else { return }
        applyServerState(
            response,
            allowPublicIDUpdate: allowPublicIDUpdate,
            expectedPublicIDRevision: expectedPublicIDRevision
        )
    }

    private func applyServerState(
        _ response: BackendResponse,
        allowPublicIDUpdate: Bool = false,
        expectedPublicIDRevision: Int? = nil
    ) {
        let currentPublicIDRevision = UserDefaults.standard.integer(forKey: BeansBackendSettings.publicIDRevisionKey)
        let responseIsCurrent = expectedPublicIDRevision == nil || expectedPublicIDRevision == currentPublicIDRevision
        if allowPublicIDUpdate, responseIsCurrent, let publicUserID = response.publicUserID {
            let previous = DeviceIdentity.publicID
            DeviceIdentity.updatePublicID(publicUserID)
            if previous != DeviceIdentity.publicID {
                let revision = UserDefaults.standard.integer(forKey: BeansBackendSettings.publicIDRevisionKey)
                UserDefaults.standard.set(revision &+ 1, forKey: BeansBackendSettings.publicIDRevisionKey)
            }
        }
        if let exclusiveID = response.exclusiveID {
            UserDefaults.standard.set(exclusiveID, forKey: BeansBackendSettings.exclusiveIDKey)
        }
        if let badgeStyle = response.exclusiveBadgeStyle {
            UserDefaults.standard.set(badgeStyle.rawValue, forKey: BeansBackendSettings.exclusiveIDBadgeStyleKey)
        }
        if response.listeningSeconds != nil || response.listeningPlayCount != nil {
            PlayerManager.mergeServerListeningStats(
                seconds: response.listeningSeconds,
                playCount: response.listeningPlayCount
            )
            NotificationCenter.default.post(name: .beansListeningStatsDidSync, object: nil)
        }
        if let blocked = response.blocked {
            let previous = UserDefaults.standard.bool(forKey: BeansBackendSettings.blockedKey)
            UserDefaults.standard.set(blocked, forKey: BeansBackendSettings.blockedKey)
            if previous != blocked {
                NotificationCenter.default.post(name: .beansBackendBlockStateDidChange, object: nil)
            }
        }
        if let downloadUnlocked = response.downloadUnlocked {
            // 后台取消解锁时会明确返回 false；不能只处理 true，
            // 否则客户端会永久保留上一次的下载权限。
            UserDefaults.standard.set(downloadUnlocked, forKey: BeansBackendSettings.downloadUnlockKey)
        }
        if let downloadGlobalEnabled = response.downloadGlobalEnabled {
            UserDefaults.standard.set(downloadGlobalEnabled, forKey: BeansBackendSettings.downloadGlobalUnlockKey)
        }
        FeedbackHistoryStore.shared.receiveServerReplies(response.feedbackReplies)
    }

    private func decodeResponse(_ data: Data) throws -> BackendResponse {
        guard !data.isEmpty else { return BackendResponse() }
        do {
            return try JSONDecoder().decode(BackendResponse.self, from: data)
        } catch {
            throw BackendRequestError.invalidResponse
        }
    }
}

private struct BackendResponse: Decodable {
    let ok: Bool?
    let message: String?
    let publicUserID: String?
    let exclusiveID: Bool?
    let exclusiveBadgeStyle: BeansExclusiveIDBadgeStyle?
    let listeningSeconds: Int?
    let listeningPlayCount: Int?
    let blocked: Bool?
    let downloadUnlocked: Bool?
    let downloadGlobalEnabled: Bool?
    let feedbackID: String?
    let submittedAt: String?
    let feedbackReplies: [FeedbackReply]

    enum CodingKeys: String, CodingKey {
        case ok, message, blocked
        case publicUserID = "public_user_id"
        case exclusiveID = "exclusive_id"
        case exclusiveBadgeStyle = "exclusive_badge_style"
        case listeningSeconds = "listening_seconds"
        case listeningPlayCount = "listening_play_count"
        case downloadUnlocked = "download_unlocked"
        case downloadGlobalEnabled = "download_global_enabled"
        case feedbackID = "feedback_id"
        case submittedAt = "submitted_at"
        case feedbackReplies = "feedback_replies"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        publicUserID = try container.decodeIfPresent(String.self, forKey: .publicUserID)
        exclusiveID = try container.decodeIfPresent(Bool.self, forKey: .exclusiveID)
        exclusiveBadgeStyle = try container.decodeIfPresent(BeansExclusiveIDBadgeStyle.self, forKey: .exclusiveBadgeStyle)
        listeningSeconds = try container.decodeIfPresent(Int.self, forKey: .listeningSeconds)
        listeningPlayCount = try container.decodeIfPresent(Int.self, forKey: .listeningPlayCount)
        blocked = try container.decodeIfPresent(Bool.self, forKey: .blocked)
        downloadUnlocked = try container.decodeIfPresent(Bool.self, forKey: .downloadUnlocked)
        downloadGlobalEnabled = try container.decodeIfPresent(Bool.self, forKey: .downloadGlobalEnabled)
        feedbackID = try container.decodeIfPresent(String.self, forKey: .feedbackID)
        submittedAt = try container.decodeIfPresent(String.self, forKey: .submittedAt)
        feedbackReplies = try container.decodeIfPresent(
            [FeedbackReply].self,
            forKey: .feedbackReplies
        ) ?? []
    }

    init() {
        ok = nil
        message = nil
        publicUserID = nil
        exclusiveID = nil
        exclusiveBadgeStyle = nil
        listeningSeconds = nil
        listeningPlayCount = nil
        blocked = nil
        downloadUnlocked = nil
        downloadGlobalEnabled = nil
        feedbackID = nil
        submittedAt = nil
        feedbackReplies = []
    }
}

private struct BeansGlobalDownloadResponse: Decodable {
    let ok: Bool?
    let message: String?
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case ok, message
        case enabled = "download_global_enabled"
    }
}

private struct BeansDeveloperAnnouncementResponse: Decodable {
    let ok: Bool?
    let message: String?
    let announcement: BeansDeveloperAnnouncement

    enum CodingKeys: String, CodingKey {
        case ok, message
        case announcement
        case enabled = "announcement_enabled"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        announcement = BeansDeveloperAnnouncement(
            announcement: try container.decodeIfPresent(String.self, forKey: .announcement) ?? "",
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            updatedAt: try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        )
    }
}

private struct BeansExclusiveAccessResponse: Decodable {
    let ok: Bool?
    let message: String?
    let records: [BeansExclusiveAccessRecord]

    enum CodingKeys: String, CodingKey {
        case ok, message, records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        records = try container.decodeIfPresent([BeansExclusiveAccessRecord].self, forKey: .records) ?? []
    }
}

private struct BeansExclusiveAccessStatusResponse: Decodable {
    let ok: Bool?
    let message: String?
    let record: BeansExclusiveAccessRecord?
}

private struct BeansDownloadAccessResponse: Decodable {
    let ok: Bool?
    let message: String?
    let records: [BeansDownloadAccessRecord]

    enum CodingKeys: String, CodingKey {
        case ok, message, records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        records = try container.decodeIfPresent([BeansDownloadAccessRecord].self, forKey: .records) ?? []
    }
}

private struct FeedbackListResponse: Decodable {
    let ok: Bool?
    let message: String?
    let feedback: [FeedbackServerRecord]

    enum CodingKeys: String, CodingKey {
        case ok, message, feedback
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        feedback = try container.decodeIfPresent([FeedbackServerRecord].self, forKey: .feedback) ?? []
    }
}

private enum BackendRequestError: LocalizedError {
    case missingRequiredFields
    case attachmentTooLarge
    case invalidResponse
    case httpStatus(Int)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredFields:
            return beansLocalized("请填写全部必填项。", "Please complete all required fields.")
        case .attachmentTooLarge:
            return beansLocalized("单个附件不能超过 50 MB。", "Each attachment must be 50 MB or smaller.")
        case .invalidResponse:
            return beansLocalized("服务器返回异常，请稍后重试。", "The server returned an invalid response. Please try again.")
        case .httpStatus:
            return beansLocalized("提交失败，请稍后重试。", "Submission failed. Please try again.")
        case .server(let message):
            return message
        }
    }
}

private extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append(value.data(using: .utf8)!)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(
        name: String,
        filename: String,
        contentType: String,
        data: Data,
        boundary: String
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
