import Foundation
import UIKit

/// 闪退检测与崩溃日志：捕获未捕获异常 / 崩溃信号，并在下次启动时检测上次是否异常退出。
/// 崩溃信息写入 Documents/BeansLogs/crash-日期.log，同时写入 App 内日志，便于反馈排查。
final class CrashReporter {
    static let shared = CrashReporter()

    /// 启动是否仍在进行（正常完成前为 true；若上次退出时仍为 true，说明可能闪退）
    private static let launchKey = "beans.launchInProgress"
    /// 关键界面展示时保留的诊断标记；仅异常中断时会留到下次启动。
    private static let activeContextKey = "beans.crash.activeContext"
    private static let activeContextTimeKey = "beans.crash.activeContextTime"

    private init() {
        // 检测上次启动是否正常完成
        let wasInProgress = UserDefaults.standard.bool(forKey: Self.launchKey)
        if wasInProgress {
            BeansLogger.shared.log("⚠ 检测到上次运行异常退出（疑似闪退）。崩溃详情见 crash-*.log，可导出反馈排查", level: .error)
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
    }

    /// 界面正常关闭后移除诊断标记，避免把用户主动退出误判为闪退。
    func endContext(_ context: String) {
        guard UserDefaults.standard.string(forKey: Self.activeContextKey) == context else { return }
        UserDefaults.standard.removeObject(forKey: Self.activeContextKey)
        UserDefaults.standard.removeObject(forKey: Self.activeContextTimeKey)
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

    private static let contextTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
