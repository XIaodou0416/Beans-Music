import Foundation
import SwiftUI
import UIKit

enum BilibiliDetailDiagnostics {
    // Keep detail failures available on-device so older iOS releases can be diagnosed without Xcode.
    private static let queue = DispatchQueue(label: "beans.bilibili.detail-diagnostics")
    private static let fileURL: URL = {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("bilibili-detail.log")
    }()

    static func record(_ event: String) {
        BeansDiagnostics.shared.recordAction("B站详情：\(event)")
        queue.async {
            let formatter = ISO8601DateFormatter()
            let line = "[\(formatter.string(from: Date()))] \(event)\n"
            guard let data = line.data(using: .utf8) else { return }
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    static func read() -> String {
        queue.sync {
            (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "暂无详情诊断记录"
        }
    }

    static func clear() {
        queue.async { try? FileManager.default.removeItem(at: fileURL) }
    }
}

struct BilibiliDetailLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var log = ""

    var body: some View {
        BeansNavigationStack {
            ScrollView {
                Text(log.isEmpty ? "正在读取日志..." : log)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .navigationTitle("详情诊断日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("复制") { UIPasteboard.general.string = log }
                }
            }
        }
        .task { log = BilibiliDetailDiagnostics.read() }
    }
}

