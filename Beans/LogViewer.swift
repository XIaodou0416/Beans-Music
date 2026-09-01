import SwiftUI
import UIKit


/// 日志查看器：展示内存日志（可按级别筛选）或导入的日志文件原文
struct LogViewerSheet: View {
    @ObservedObject private var logger = BeansLogger.shared
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("beans.language") private var languageRaw = AppLanguage.chinese.rawValue
    let importedText: String?

    @State private var filter: BeansLogLevel? = nil
    @State private var showShare = false

    private var filtered: [BeansLogEntry] {
        guard let filter else { return logger.entries }
        return logger.entries.filter { $0.level == filter }
    }

    private var isEnglish: Bool { languageRaw == AppLanguage.english.rawValue }

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                VStack(spacing: 0) {
                    if let importedText {
                        ScrollView {
                            Text(isEnglish ? BeansLogLocalizer.english(importedText) : importedText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.beansLabel)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                        .beansScrollIndicatorsHidden()
                    } else {
                        Picker("级别", selection: $filter) {
                            Text("全部").tag(nil as BeansLogLevel?)
                            ForEach(BeansLogLevel.allCases, id: \.self) { level in
                                Text(level.rawValue).tag(level as BeansLogLevel?)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        if filtered.isEmpty {
                            EmptyStateView(icon: "doc.text", text: "暂无日志")
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 6) {
                                    ForEach(filtered) { entry in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(entry.level.rawValue)
                                                .font(BeansFont.appFont(9, .bold, .monospaced))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Capsule().fill(entry.level.tint))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(isEnglish ? BeansLogLocalizer.english(entry.message) : entry.message)
                                                    .font(BeansFont.appFont(12, .medium))
                                                    .foregroundStyle(Color.beansLabel)
                                                    .textSelection(.enabled)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                Text(BeansLogger.dateString(entry.date))
                                                    .font(BeansFont.appFont(9, .regular, .monospaced))
                                                    .foregroundStyle(Color.beansComment)
                                            }
                                        }
                                        .padding(9)
                                        .background { BeansSurface(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 30)
                            }
                            .beansScrollIndicatorsHidden()
                        }
                    }
                }
            }
            .navigationTitle(importedText == nil ? "日志" : "导入的日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            if let importedText {
                                UIPasteboard.general.string = importedText
                            } else {
                                UIPasteboard.general.string = logger.fullText
                            }
                            ToastCenter.shared.show("日志已复制")
                        } label: {
                            Label("复制全部", systemImage: "doc.on.doc")
                        }
                        if importedText == nil {
                            Button {
                                showShare = true
                            } label: {
                                Label("导出日志", systemImage: "square.and.arrow.up")
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .background {
            HighRefreshConfigurator()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .modifier(BeansSheetModifier(detents: [.large], dragIndicator: true))
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [BeansLogger.shared.exportLogURL()])
        }
    }
}

private enum BeansLogLocalizer {
    static func english(_ text: String) -> String {
        var output = text
        for (source, replacement) in replacements {
            output = output.replacingOccurrences(of: source, with: replacement)
        }
        return output
    }

    private static let replacements: [(String, String)] = [
        ("Beans Music 启动", "Beans Music started"),
        ("版本", "version"),
        ("搜索完成", "Search completed"),
        ("搜索失败", "Search failed"),
        ("搜索", "Search"),
        ("结果", "results"),
        ("开始播放", "Start playback"),
        ("播放成功", "Playback started"),
        ("播放失败自动下一首", "Playback failed, auto-skipping to next"),
        ("播放失败", "Playback failed"),
        ("播放地址加载失败", "Failed to load playback URL"),
        ("播放地址为空", "Playback URL is empty"),
        ("无法解析播放地址", "Unable to resolve playback URL"),
        ("解析播放地址失败", "Failed to resolve playback URL"),
        ("官方地址实际不可播放", "Official URL is not playable"),
        ("第三方音源", "third-party source"),
        ("第三方", "third-party"),
        ("音源调用上限", "source API limit"),
        ("地址失效", "URL expired"),
        ("音质", "quality"),
        ("免费听歌", "free listening"),
        ("官方受限", "officially restricted"),
        ("网易云", "NetEase Cloud Music"),
        ("QQ 音乐", "QQ Music"),
        ("QQ音乐", "QQ Music"),
        ("酷狗音乐", "Kugou Music"),
        ("酷狗", "Kugou"),
        ("歌单同步", "playlist sync"),
        ("歌单", "playlist"),
        ("登录成功", "signed in"),
        ("未登录", "not signed in"),
        ("已登录", "signed in"),
        ("同步中", "syncing"),
        ("请求失败", "request failed"),
        ("加载失败", "loading failed"),
        ("加载完成", "loading completed"),
        ("导出备份", "export backup"),
        ("恢复配置备份", "restore backup"),
        ("日志已清空", "logs cleared"),
        ("日志已复制", "logs copied"),
        ("返回", "returned"),
        ("命中", "matched"),
        ("未命中", "not matched"),
        ("已启用", "enabled"),
        ("未启用", "disabled"),
        ("有", "yes"),
        ("无", "no"),
        ("开", "on"),
        ("关", "off"),
        ("首", "songs"),
        ("平台", "platform"),
        ("歌曲", "song"),
        ("原因", "reason"),
        ("错误", "error"),
        ("状态", "status")
    ]
}
