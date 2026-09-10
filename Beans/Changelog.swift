import SwiftUI

// MARK: - 版本更新日志（设置页与首次更新弹窗使用）

struct VersionLog: Identifiable {
    let id: String
    let version: String
    let title: String
    let notices: [String]
    let features: [String]
    let fixes: [String]
    let imageURL: URL?
    let textColorHex: String?

    init(id: String, version: String, title: String, notices: [String] = [], features: [String], fixes: [String], imageURL: URL? = nil, textColorHex: String? = nil) {
        self.id = id
        self.version = version
        self.title = title
        self.notices = notices
        self.features = features
        self.fixes = fixes
        self.imageURL = imageURL
        self.textColorHex = textColorHex
    }
}

enum ChangelogStore {
    static let lastSeenKey = "beans.lastSeenVersion"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var lastSeenVersion: String {
        UserDefaults.standard.string(forKey: lastSeenKey) ?? ""
    }

    static func markSeen() {
        UserDefaults.standard.set(currentVersion, forKey: lastSeenKey)
        UserDefaults.standard.synchronize()
    }

    static var shouldShowWhatsNew: Bool {
        lastSeenVersion != currentVersion
    }

    static var latest: VersionLog? { logs.first }

    /// 更新日志从 GitHub Releases 读取；网络不可用时继续显示内置历史记录。
    static func fetchRemoteLatest() async -> VersionLog? {
        guard let remote = try? await UpdateChecker.fetchLatest() else { return nil }
        return versionLog(from: remote)
    }

    static func fetchRemoteHistory() async -> [VersionLog] {
        guard let remoteLogs = try? await UpdateChecker.fetchHistory() else { return [] }
        return remoteLogs.map { versionLog(from: $0) }
    }

    private static func versionLog(from remote: UpdateChecker.ReleaseInfo) -> VersionLog {
        let notes = remote.body
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return VersionLog(
            id: "server-\(remote.version)",
            version: remote.version,
            title: remote.name,
            features: notes,
            fixes: [],
            imageURL: remote.notesImageURL,
            textColorHex: remote.notesTextColorHex
        )
    }

    static let logs: [VersionLog] = [
        VersionLog(
            id: "1.6.7",
            version: "1.6.7",
            title: "主页、播放器与缓存体验优化",
            notices: [
                "建议更新时卸载后重新安装，不要覆盖安装，否则可能出现部分问题。",
                "不是最新版请不要反馈问题，旧版本不再维护。",
                "本软件不提供下载服务，请支持官方网易云音乐、QQ 音乐和酷狗音乐平台。"
            ],
            features: [
                "新增“新碟上架”和“歌手”板块",
                "新增歌单搜索，并将歌单广场独立为单独页面",
                "“我的”入口移至右上角，支持自定义昵称和头像",
                "新增灵动岛与控制中心显示开关",
                "新增多项缓存机制，提升加载速度和使用体验",
                "优化底部栏动画，适配 Apple Music 风格的自动收缩效果",
                "Apple Music 风格主页新增磨砂背景",
                "账号入口移至设置页面",
                "修改默认强调色",
                "优化音源播放与切歌速度",
                "更新底部栏图标样式",
                "移除歌单液态容器"
            ],
            fixes: [
                "修复低版本系统无法调节进度条的问题",
                "修复歌词与音乐进度不同步的问题",
                "修复自定义排序后重新打开应用失效的问题"
            ]
        ),
        VersionLog(
            id: "1.6.6",
            version: "1.6.6",
            title: "歌单广场与播放体验优化",
            features: [
                "新增网易云和 QQ 音乐歌单广场搜索功能",
                "优化歌曲封面缓存",
                "优化歌词滑动后不返回当前播放位置的问题",
                "优化整体流畅性，低系统表现以实际测试为准",
                "优化网易云私人漫游问题，遇到问题可使用心动模式",
                "简化搜索界面，移除均衡器注释",
                "更换酷狗音乐歌单广场接口",
                "整体以优化和问题修复为主"
            ],
            fixes: [
                "修复 QQ 音乐本身有会员但无法播放的问题",
                "修复 iOS 26 以下系统无法返回的问题"
            ]
        ),
        VersionLog(
            id: "1.6.5.1",
            version: "1.6.5.1",
            title: "音源与歌单体验修复",
            features: [
                "修复歌单页播放器无法返回的问题",
                "删除内置音源功能和填写密钥（可从密钥后台复制链接导入）",
                "持续优化 QQ 音源问题",
                "增加歌单、主页和排行榜缓存，减少重复加载"
            ],
            fixes: [
                "软件不提供任何下载服务，不会导入音源的可在群里反馈"
            ]
        ),
        VersionLog(
            id: "1.6.5",
            version: "1.6.5",
            title: "音源播放修复",
            features: [
                "新增网易云免费音源"
            ],
            fixes: [
                "修复 QQ 音乐音源不能播放的问题",
                "修复自定义导入音源不能播放的问题"
            ]
        ),
    ]
}

// MARK: - 更新说明弹窗

struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var remoteLog: VersionLog?

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: ThemeStore.shared.backgroundSyncAll ? ThemeStore.shared.customBackground : nil)
                ScrollView {
                    if let log = remoteLog ?? ChangelogStore.latest {
                        VersionLogCard(log: log)
                            .padding(16)
                    }
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle("更新说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始使用") {
                        ChangelogStore.markSeen()
                        dismiss()
                    }
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(Color.beansAmber)
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large]))
        .task {
            remoteLog = await ChangelogStore.fetchRemoteLatest()
        }
        .onDisappear {
            ChangelogStore.markSeen()
        }
    }
}

struct ChangelogListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var remoteLogs: [VersionLog] = []

    var body: some View {
        let remoteVersions = Set(remoteLogs.map(\.version))
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: ThemeStore.shared.backgroundSyncAll ? ThemeStore.shared.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(remoteLogs) { log in
                            VersionLogCard(log: log)
                        }
                        ForEach(ChangelogStore.logs.filter { log in
                            !remoteVersions.contains(log.version)
                        }) { log in
                            VersionLogCard(log: log)
                        }
                    }
                    .padding(16)
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle("更新日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.medium, .large]))
        .task {
            remoteLogs = await ChangelogStore.fetchRemoteHistory()
        }
    }
}

private struct VersionLogCard: View {
    let log: VersionLog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("v\(log.version)")
                    .font(BeansFont.appFont(16, .bold))
                    .foregroundStyle(Color.beansAmber)
                Text(log.title)
                    .font(BeansFont.appFont(14, .semibold))
                    .foregroundStyle(textColor)
            }
            if let imageURL = log.imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else if phase.error != nil {
                        EmptyView()
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if !log.notices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(log.notices, id: \.self) { notice in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.top, 1)
                            Text(notice)
                                .font(BeansFont.appFont(13, .semibold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.red.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            if !log.features.isEmpty {
                logSection(title: "新增功能", icon: "plus.circle.fill", items: log.features)
            }
            if !log.fixes.isEmpty {
                Divider().overlay(Color.beansComment.opacity(0.15))
                logSection(title: "问题修复", icon: "checkmark.circle.fill", items: log.fixes)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .beansCardShadow(radius: 9, y: 3)
    }

    private func logSection(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(BeansFont.appFont(14, .bold))
                .foregroundStyle(Color.beansAmber)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.beansAmber)
                        .padding(.top, 2)
                    Text(LocalizedStringKey(item))
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(textColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var textColor: Color {
        if let raw = log.textColorHex, let color = Color(hex: raw) { return color }
        return Color.beansLabel
    }
}
