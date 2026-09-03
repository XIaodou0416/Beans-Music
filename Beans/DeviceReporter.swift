import Foundation
import UIKit

struct FeedbackSubmissionResult: Sendable {
    let downloadUnlocked: Bool
}

enum BeansBackendSettings {
    static let downloadUnlockKey = "beans.downloadFeatureUnlocked"
    static let blockedKey = "beans.backend.userBlocked"
}

/// 启动时向后台上报基础设备信息；IP 由后台从请求中获取。
@MainActor
final class DeviceReporter {
    static let shared = DeviceReporter()

    private var reported = false
    private let apiEndpoint = URL(string: "http://189.24.78.193/beans")!
    private let legacyHeartbeatEndpoint = URL(string: "http://189.24.78.193/beans/heartbeat")!

    private init() {}

    func reportLaunch() async {
        guard !reported else { return }
        reported = true
        var payload = devicePayload()
        payload["event"] = "register"

        do {
            let data = try await postJSON(to: endpoint(for: "register"), payload: payload)
            applyServerState(from: data)
        } catch {
            // 保留已有心跳接口作为兼容兜底；新后端部署前不影响原有启动上报。
            do {
                let data = try await postJSON(to: legacyHeartbeatEndpoint, payload: payload)
                applyServerState(from: data)
            } catch {
                BeansLogger.shared.log("设备启动信息上报失败：\(error.localizedDescription)", level: .debug)
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
        return FeedbackSubmissionResult(downloadUnlocked: response.downloadUnlocked == true)
    }

    private func endpoint(for action: String) -> URL {
        apiEndpoint.appendingPathComponent(action)
    }

    private func devicePayload() -> [String: String] {
        let device = UIDevice.current
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return [
            "user_id": DeviceIdentity.userID,
            "model": DeviceIdentity.hardwareModel,
            "device_name": device.model,
            "system": "\(device.systemName) \(device.systemVersion)",
            "system_version": device.systemVersion,
            "app_version": UpdateChecker.currentVersion,
            "app_build": build
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
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return data
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw BackendRequestError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw BackendRequestError.httpStatus(http.statusCode)
        }
    }

    private func applyServerState(from data: Data) {
        guard let response = try? decodeResponse(data) else { return }
        applyServerState(response)
    }

    private func applyServerState(_ response: BackendResponse) {
        if let blocked = response.blocked {
            UserDefaults.standard.set(blocked, forKey: BeansBackendSettings.blockedKey)
        }
        if response.downloadUnlocked == true {
            UserDefaults.standard.set(true, forKey: BeansBackendSettings.downloadUnlockKey)
        }
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
    let blocked: Bool?
    let downloadUnlocked: Bool?

    enum CodingKeys: String, CodingKey {
        case ok, message, blocked
        case downloadUnlocked = "download_unlocked"
    }

    init() {
        ok = nil
        message = nil
        blocked = nil
        downloadUnlocked = nil
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
