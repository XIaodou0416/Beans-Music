import Foundation
import UIKit

/// 启动时向后台上报基础设备信息；IP 由后台从请求中获取。
@MainActor
final class DeviceReporter {
    static let shared = DeviceReporter()
    private var reported = false
    private let endpoint = URL(string: "http://189.24.78.193/beans/heartbeat")!

    private init() {}

    func reportLaunch() async {
        guard !reported else { return }
        reported = true
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        let device = UIDevice.current
        let payload: [String: String] = [
            "model": device.model,
            "system": "\(device.systemName) \(device.systemVersion)",
            "app_version": UpdateChecker.currentVersion
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            BeansLogger.shared.log("设备启动信息上报失败：\(error.localizedDescription)", level: .debug)
        }
    }
}
