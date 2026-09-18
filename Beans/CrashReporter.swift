import Foundation
import UIKit
import MetricKit

/// 闪退检测与崩溃日志：捕获未捕获异常 / 崩溃信号，并在下次启动时检测上次是否异常退出。
/// 崩溃信息写入 Documents/BeansLogs/crash-日期.log，同时写入 App 内日志，便于反馈排查。
final class CrashReporter {
    static let shared = CrashReporter()

    /// 启动是否仍在进行（正常完成前为 true；若上次退出时仍为 true，说明可能闪退）
    private static let launchKey = "beans.launchInProgress"
    /// 关键界面展示时保留的诊断标记；仅异常中断时会留到下次启动。
    private static let activeContextKey = "beans.crash.activeContext"
    private static let activeContextTimeKey = "beans.crash.activeContextTime"
    private static let recentEventsKey = "beans.crash.recentEvents"

    private init() {
        // 检测上次启动是否正常完成
        let wasInProgress = UserDefaults.standard.bool(forKey: Self.launchKey)
        if wasInProgress {
            let events = UserDefaults.standard.stringArray(forKey: Self.recentEventsKey) ?? []
            let eventText = events.isEmpty ? "无已记录操作" : events.joined(separator: "\n")
            Self.writeCrash("""
            [异常退出]
            原因：系统未在应用正常完成启动前结束进程；当前日志不包含系统调用栈。
            最近操作：
            \(eventText)
            """)
            BeansLogger.shared.log("⚠ 检测到上次运行异常退出，已生成可读诊断日志", level: .error)
        }
        if let context = UserDefaults.standard.string(forKey: Self.activeContextKey), !context.isEmpty {
            let timestamp = UserDefaults.standard.string(forKey: Self.activeContextTimeKey) ?? "未知"
            Self.writeCrash("[疑似异常退出] 最后活跃界面：\(context)\n记录时间：\(timestamp)")
            UserDefaults.standard.removeObject(forKey: Self.activeContextKey)
            UserDefaults.standard.removeObject(forKey: Self.activeContextTimeKey)
        }
        UserDefaults.standard.set(true, forKey: Self.launchKey)

        // 未捕获异常（NSException）
        NSSetUncaughtExceptionHandler { exception in
            let detail = """
            [未捕获异常] \(exception.name.rawValue)
            reason: \(exception.reason ?? "无")
            stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """
            CrashReporter.writeCrash(detail)
        }

        // 崩溃信号
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE] {
            signal(sig, Self.signalHandler)
        }
    }

    /// 启动正常完成后调用，标记本次启动成功（避免下次误报闪退）
    func markLaunchCompleted() {
        UserDefaults.standard.set(false, forKey: Self.launchKey)
    }

    /// 标记关键界面已开始展示，异常退出后会在下次启动写入本地诊断日志。
    func beginContext(_ context: String) {
        UserDefaults.standard.set(context, forKey: Self.activeContextKey)
        UserDefaults.standard.set(Self.contextTimestamp.string(from: Date()), forKey: Self.activeContextTimeKey)
        recordEvent("进入界面：\(context)")
    }

    /// 界面正常关闭后移除诊断标记，避免把用户主动退出误判为闪退。
    func endContext(_ context: String) {
        guard UserDefaults.standard.string(forKey: Self.activeContextKey) == context else { return }
        UserDefaults.standard.removeObject(forKey: Self.activeContextKey)
        UserDefaults.standard.removeObject(forKey: Self.activeContextTimeKey)
        recordEvent("离开界面：\(context)")
    }

    /// 保存最近的用户操作，供下次启动的异常报告定位触发点。
    /// 只记录功能名称，不记录歌曲、账号、网络请求或凭据。
    func recordEvent(_ event: String) {
        let stamp = Self.contextTimestamp.string(from: Date())
        var events = UserDefaults.standard.stringArray(forKey: Self.recentEventsKey) ?? []
        events.append("[\(stamp)] \(event)")
        if events.count > 40 {
            events.removeFirst(events.count - 40)
        }
        UserDefaults.standard.set(events, forKey: Self.recentEventsKey)
    }

    /// 崩溃信号处理：记录信号类型后恢复默认并重新抛出，保持系统崩溃行为
    private static let signalHandler: @convention(c) (Int32) -> Void = { sig in
        let names: [Int32: String] = [SIGABRT: "SIGABRT", SIGSEGV: "SIGSEGV", SIGBUS: "SIGBUS", SIGILL: "SIGILL", SIGFPE: "SIGFPE"]
        CrashReporter.writeCrash("[崩溃信号] \(names[sig] ?? "\(sig)")")
        signal(sig, SIG_DFL)
        raise(sig)
    }

    /// 崩溃 / 异常内容写入崩溃日志文件（尽量简单，避免依赖过多）
    static func writeCrash(_ text: String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BeansLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let stamp = formatter.string(from: Date())

        let file = dir.appendingPathComponent("crash-\(stamp.replacingOccurrences(of: ":", with: "-")).log")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let device = UIDevice.current.model
        let os = UIDevice.current.systemName + " " + UIDevice.current.systemVersion
        let content = """
        Beans Music 崩溃日志
        时间：\(stamp)
        版本：\(version) (build \(build))
        设备：\(device)
        系统：\(os)
        -------------------------
        \(text)
        """
        try? content.data(using: .utf8)?.write(to: file, options: .atomic)

        // 同时写入 App 内日志，便于直接查看
        BeansLogger.shared.log("检测到崩溃/异常：\(text.components(separatedBy: "\n").first ?? text)", level: .error)
    }

    /// 保存系统在下次启动交付的诊断数据，供定位未捕获的原生崩溃使用。
    static func writeMetricDiagnostic(_ data: Data) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BeansLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let file = dir.appendingPathComponent("metric-diagnostic-\(formatter.string(from: Date())).json")
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        if let summary = metricSummary(from: data) {
            let summaryFile = file.deletingPathExtension().appendingPathExtension("txt")
            try? summary.write(to: summaryFile, atomically: true, encoding: .utf8)
        }
        BeansLogger.shared.log("已保存系统诊断文件：\(file.lastPathComponent)", level: .error)
    }

    /// 把 MetricKit JSON 中最有用的字段提取成可直接阅读的诊断文本。
    private static func metricSummary(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { return nil }

        var lines = [
            "Beans Music 系统诊断摘要",
            "时间：\(contextTimestamp.string(from: Date()))"
        ]
        appendDiagnosticFields(from: root, to: &lines)
        return lines.count > 2 ? lines.joined(separator: "\n") + "\n" : nil
    }

    private static func appendDiagnosticFields(from value: Any, to lines: inout [String]) {
        if let dictionary = value as? [String: Any] {
            let interestingKeys = [
                "exceptionType", "exceptionCode", "signal", "terminationReason",
                "diagnosticType", "callStackTree", "hangDuration", "applicationVersion",
                "osVersion", "deviceType"
            ]
            for key in interestingKeys {
                if let item = dictionary[key] {
                    let text: String
                    if let string = item as? String {
                        text = string
                    } else if let number = item as? NSNumber {
                        text = number.stringValue
                    } else if let nested = item as? [String: Any], key == "callStackTree" {
                        text = "调用栈节点=\(countCallStackNodes(nested))"
                    } else {
                        continue
                    }
                    lines.append("\(key)：\(text)")
                }
            }
            for child in dictionary.values {
                appendDiagnosticFields(from: child, to: &lines)
            }
        } else if let array = value as? [Any] {
            for child in array {
                appendDiagnosticFields(from: child, to: &lines)
            }
        }
    }

    private static func countCallStackNodes(_ value: [String: Any]) -> Int {
        var count = 1
        if let callStack = value["callStacks"] as? [[String: Any]] {
            count += callStack.count
        }
        if let nested = value["callStackTree"] as? [String: Any] {
            count += countCallStackNodes(nested)
        }
        return count
    }

    private static let contextTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

/// MetricKit 会在下次启动时交付系统采集的崩溃、卡死等原生诊断；不记录账号或播放数据。
final class CrashMetricCollector: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashMetricCollector()

    private override init() {
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            CrashReporter.writeMetricDiagnostic(payload.jsonRepresentation())
        }
    }
}
