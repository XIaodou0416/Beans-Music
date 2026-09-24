import Foundation
import SwiftUI
import UIKit
import CryptoKit

/// 全局诊断中心：记录用户操作、页面路由、网络摘要、性能快照和最近事件。
/// iOS 不能在进程被系统直接终止时可靠地拦截所有 Swift trap，因此原生崩溃仍由
/// CrashReporter 与 MetricKit 负责，这里保存崩溃前的上下文，方便下次启动定位。
final class BeansDiagnostics: ObservableObject {
    static let shared = BeansDiagnostics()

    @Published private(set) var breadcrumbCount = 0
    @Published private(set) var lastRoute = "启动"
    @Published private(set) var lastSnapshotDate: Date?
    @Published private(set) var lastCrashFile: URL?
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }

    private static let enabledKey = "beans.diagnostics.enabled"
    private let lock = NSLock()
    private var breadcrumbs: [String] = []
    private var currentRoute = "启动"
    private var lastAction = "启动"
    private var started = false
    private var performanceTimer: DispatchSourceTimer?
    private var mainBeat = Date()
    private let maxBreadcrumbs = 80

    private init() {
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        lastCrashFile = Self.latestCrashFile()
    }

    func start() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()

        UIDevice.current.isBatteryMonitoringEnabled = true
        route("应用启动")
        recordAction("应用启动")
        startPerformanceSampler()
    }

    func route(_ name: String, file: String = #fileID, line: Int = #line, function: String = #function) {
        lock.lock()
        currentRoute = name
        lastAction = "进入页面：\(name)"
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.lastRoute = name }
        record("route=\(name)", level: .info, file: file, line: line, function: function)
    }

    func recordAction(_ action: String, file: String = #fileID, line: Int = #line, function: String = #function) {
        lock.lock()
        lastAction = action
        lock.unlock()
        record("action=\(action)", level: .debug, file: file, line: line, function: function)
    }

    func recordNetwork(url: URL, method: String, status: Int? = nil, duration: TimeInterval? = nil, error: String? = nil,
                       file: String = #fileID, line: Int = #line, function: String = #function) {
        var message = "network method=\(method) url=\(url.absoluteString)"
        if let status { message += " status=\(status)" }
        if let duration { message += String(format: " duration=%.0fms", duration * 1000) }
        if let error { message += " error=\(redact(error))" }
        record(message, level: error == nil ? .debug : .error, file: file, line: line, function: function)
    }

    func recordError(_ message: String, file: String = #fileID, line: Int = #line, function: String = #function) {
        record("error=\(redact(message))", level: .error, file: file, line: line, function: function)
    }

    func snapshot(reason: String = "手动快照") -> String {
        let text = diagnosticContext(reason: reason)
        record(text, level: .info)
        lastSnapshotDate = Date()
        return text
    }

    func exportLogURL() -> URL {
        let directory = logDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let file = directory.appendingPathComponent("BeansDiagnostics-\(formatter.string(from: Date())).txt")
        let crashText = Self.crashFiles(in: directory).prefix(6).compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n\n")
        let content = "Beans Music 全局诊断日志\n\(diagnosticContext(reason: \"导出\"))\n\n最近结构化日志：\n\(BeansLogger.shared.fullText)\n\n最近崩溃与系统诊断：\n\(crashText.isEmpty ? \"暂无\" : crashText)\n"
        try? content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func clear() {
        BeansLogger.shared.clear()
        lock.lock()
        breadcrumbs.removeAll()
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: "beans.crash.recentEvents")
        lastCrashFile = nil
        breadcrumbCount = 0
    }

    func record(_ message: String, level: BeansLogLevel = .debug, file: String = #fileID, line: Int = #line, function: String = #function) {
        guard enabled || level == .error || level == .fatal else { return }
        let context = diagnosticContext(reason: message, includeMetrics: false)
        let lineText = "\(context) file=\(URL(fileURLWithPath: file).lastPathComponent):\(line) function=\(function) content=\(redact(message))"
        lock.lock()
        breadcrumbs.append(lineText)
        if breadcrumbs.count > maxBreadcrumbs { breadcrumbs.removeFirst(breadcrumbs.count - maxBreadcrumbs) }
        let recent = breadcrumbs
        lock.unlock()
        UserDefaults.standard.set(recent, forKey: "beans.diagnostics.breadcrumbs")
        breadcrumbCount = recent.count
        BeansLogger.shared.log(lineText, level: level)
    }

    private func startPerformanceSampler() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "Beans.Diagnostics.Performance"))
        timer.schedule(deadline: .now() + 5, repeating: 10)
        timer.setEventHandler { [weak self] in
            guard let self, self.enabled else { return }
            DispatchQueue.main.async { [weak self] in self?.mainBeat = Date() }
            self.record(self.diagnosticContext(reason: "性能采样"), level: .debug)
        }
        performanceTimer = timer
        timer.resume()
    }

    private func diagnosticContext(reason: String, includeMetrics: Bool = true) -> String {
        lock.lock()
        let currentRoute = self.currentRoute
        let action = lastAction
        lock.unlock()
        let now = ISO8601DateFormatter().string(from: Date())
        var text = "ts=\(now) levelContext route=\(currentRoute) action=\(action) reason=\(redact(reason))"
        if includeMetrics {
            let deviceDigest = SHA256.hash(data: Data(DeviceIdentity.userID.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12)
            let battery = UIDevice.current.batteryLevel >= 0 ? String(format: "%.0f%%", UIDevice.current.batteryLevel * 100) : "unknown"
            let storage = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            text += " device=\(UIDevice.current.model) hardware=\(DeviceIdentity.hardwareModel) os=\(UIDevice.current.systemName)-\(UIDevice.current.systemVersion) app=\(BeansLogger.appVersion) build=\(Bundle.main.object(forInfoDictionaryKey: \"CFBundleVersion\") as? String ?? \"?\") deviceID=\(deviceDigest) network=\(BeansNetworkStatus.shared.connectionKind) reachable=\(BeansNetworkStatus.shared.isReachable) freeStorage=\(storage) battery=\(battery) freeMemory=\(ProcessInfo.processInfo.physicalMemory)"
        }
        return text
    }

    private func redact(_ value: String) -> String {
        value.replacingOccurrences(of: "(Authorization|Cookie|Set-Cookie|access_token|refresh_token|password|sign)[=:][^; ,&]+", with: "$1=[REDACTED]", options: .regularExpression)
    }

    private var logDirectory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BeansLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func crashFiles(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.lastPathComponent.hasPrefix("crash-") || $0.lastPathComponent.hasPrefix("metric-") }
            .sorted { modificationDate($0) > modificationDate($1) } ?? []
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func latestCrashFile() -> URL? {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BeansLogs", isDirectory: true)
        return crashFiles(in: directory).first
    }
}

struct BeansDiagnosticsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var diagnostics = BeansDiagnostics.shared
    @State private var showShare = false
    @State private var showClearConfirm = false

    var body: some View {
        BeansNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("诊断与日志", systemImage: "stethoscope")
                            .font(BeansFont.appFont(17, .semibold))
                            .foregroundStyle(Color.beansAmber)
                        Toggle("启用诊断记录", isOn: $diagnostics.enabled)
                            .tint(Color.beansAmber)
                        Text("记录页面进入、点击、网络摘要、卡顿前上下文和系统诊断。账号、Cookie、密码与令牌会自动脱敏。")
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                        diagnosticRow("最近操作", value: "\(diagnostics.breadcrumbCount) 条")
                        diagnosticRow("当前页面", value: diagnostics.lastRoute)
                        diagnosticRow("系统", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                        HStack(spacing: 10) {
                            actionButton("camera.viewfinder", "记录快照") { _ = diagnostics.snapshot() ; ToastCenter.shared.show("诊断快照已记录") }
                            actionButton("square.and.arrow.up", "导出日志") { showShare = true }
                        }
                        Button(role: .destructive) { showClearConfirm = true } label: {
                            Label("清空本地诊断日志", systemImage: "trash")
                                .font(BeansFont.appFont(13, .medium))
                        }
                    }
                    .padding(16)
                    .background { BeansGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), forceLiquid: true) }
                    Text("系统级闪退和卡死报告会在下次启动由 MetricKit 交付；应用被系统直接终止时，应用内无法保证拦截到最后一条指令。")
                        .font(BeansFont.appFont(11))
                        .foregroundStyle(Color.beansComment)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .navigationTitle("诊断与日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: [diagnostics.exportLogURL()]) }
        .confirmationDialog("确定清空本地诊断日志？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) { diagnostics.clear() }
            Button("取消", role: .cancel) {}
        }
    }

    private func diagnosticRow(_ title: String, value: String) -> some View {
        HStack { Text(title).foregroundStyle(Color.beansComment); Spacer(); Text(value).foregroundStyle(Color.beansLabel).lineLimit(1).truncationMode(.middle) }
            .font(BeansFont.appFont(12))
    }

    private func actionButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(BeansFont.appFont(13, .medium)).frame(maxWidth: .infinity).padding(.vertical, 10).background { BeansSurface(shape: Capsule()) } }
            .buttonStyle(.plain)
    }
}

