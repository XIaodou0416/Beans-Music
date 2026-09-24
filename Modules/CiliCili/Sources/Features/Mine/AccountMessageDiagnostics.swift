import Foundation
import SwiftUI
import UIKit
import Combine

nonisolated struct AccountMessageDiagnosticEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let operation: String
    let outcome: String
    let durationMilliseconds: Int
    let details: [String: String]
}

@MainActor
final class AccountMessageDiagnosticsStore: ObservableObject {
    static let shared = AccountMessageDiagnosticsStore()

    @Published private(set) var events: [AccountMessageDiagnosticEvent] = []

    private let maximumEventCount = 80

    private init() {}

    func record(
        operation: String,
        startedAt: Date,
        outcome: String,
        details: [String: String] = [:]
    ) {
        let event = AccountMessageDiagnosticEvent(
            id: UUID(),
            timestamp: Date(),
            operation: operation,
            outcome: outcome,
            durationMilliseconds: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
            details: details
        )
        events.append(event)
        if events.count > maximumEventCount {
            events.removeFirst(events.count - maximumEventCount)
        }
    }

    func reset() {
        events = []
    }

    var report: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = [
            "CiliCili 账号消息诊断",
            "generated: \(formatter.string(from: Date()))",
            "version: \(version) (\(build))",
            "events: \(events.count)",
            "success: \(events.filter { $0.outcome == "success" }.count)",
            "failure: \(events.filter { $0.outcome == "failure" }.count)",
            "",
            "关键链路",
            diagnosticSummary(
                title: "通知分页",
                operations: ["feed_page"]
            ),
            diagnosticSummary(
                title: "私信分页",
                operations: ["private_sessions", "private_messages"]
            ),
            diagnosticSummary(
                title: "已读回执",
                operations: ["private_read_ack", "private_mark_all_read", "mark_all_read"]
            ),
            diagnosticSummary(
                title: "表情面板",
                operations: ["emote_panel"]
            ),
            diagnosticSummary(
                title: "私信发送",
                operations: ["private_send_text", "private_send_image", "private_image_upload"]
            ),
            diagnosticSummary(
                title: "会话管理",
                operations: [
                    "private_session_pin",
                    "private_session_mute",
                    "private_session_remove",
                    "private_message_withdraw",
                    "private_message_report"
                ]
            ),
            "",
            "最近事件"
        ]

        if events.isEmpty {
            lines.append("  暂无记录")
        } else {
            for event in events.suffix(40).reversed() {
                let detailText = event.details
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: " ")
                let suffix = detailText.isEmpty ? "" : " · \(detailText)"
                lines.append(
                    "  \(formatter.string(from: event.timestamp)) · \(event.operation) · \(event.outcome) · \(event.durationMilliseconds)ms\(suffix)"
                )
            }
        }

        lines.append("")
        lines.append("隐私: 不包含消息正文、用户 ID、Cookie、访问令牌或私信对象信息。")
        return lines.joined(separator: "\n")
    }

    private func diagnosticSummary(title: String, operations: Set<String>) -> String {
        let matchingEvents = events.filter { operations.contains($0.operation) }
        guard !matchingEvents.isEmpty else {
            return "  \(title): 未记录"
        }
        let failures = matchingEvents.filter { $0.outcome == "failure" }.count
        let averageDuration = matchingEvents.reduce(0) { $0 + $1.durationMilliseconds } / matchingEvents.count
        let latest = matchingEvents.last
        return "  \(title): \(matchingEvents.count) 次 · 失败 \(failures) · 平均 \(averageDuration)ms · 最近 \(latest?.outcome ?? "-")"
    }
}

struct AccountMessageDiagnosticsView: View {
    @ObservedObject var store: AccountMessageDiagnosticsStore
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(store.report)
                    .appTypography(.diagnostic, fallback: .system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .hiddenInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        store.reset()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(store.events.isEmpty)
                    .accessibilityLabel("清空诊断")

                    Button {
                        UIPasteboard.general.string = store.report
                        didCopy = true
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityLabel("复制诊断")
                }
            }
        }
    }
}
