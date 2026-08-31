import SwiftUI

// MARK: - 版本更新日志（设置页与首次更新弹窗使用）

struct VersionLog: Identifiable {
    let id: String
    let version: String
    let title: String
    let notices: [String]
    let features: [String]
    let fixes: [String]

    init(id: String, version: String, title: String, notices: [String] = [], features: [String], fixes: [String]) {
        self.id = id
        self.version = version
        self.title = title
        self.notices = notices
        self.features = features
        self.fixes = fixes
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

    /// 更新日志由服务器后台维护；网络不可用时继续显示内置历史记录。
    static func fetchRemoteLatest() async -> VersionLog? {
        guard let remote = try? await UpdateChecker.fetchServerLatest() else { return nil }
        let notes = remote.body
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !remote.version.isEmpty else { return nil }
        return VersionLog(
            id: "server-\(remote.version)",
            version: remote.version,
            title: remote.name,
            features: notes,
            fixes: []
        )
    }

    static let logs: [VersionLog] = [
        VersionLog(
            id: "1.5.8",
            version: "1.5.8",
            title: "歌单同步、主页与播放器全面优化",
            features: [
                "新增网易云音乐、QQ音乐、酷狗音乐歌单一键同步到本地",
                "本地歌单支持编辑和搜索，批量选择歌曲后可添加到其他本地歌单",
                "新增 QQ 音乐热门歌单展示",
                "主页问候语支持自定义文字、颜色、大小、发光、专属字体、底部横线和上下渐变，并可逐行选择渐变颜色",
                "播放器支持左右滑动切换歌曲，新增顶部三平台排序、隐藏主页刷新/用户名/排序按钮",
                "播放器按钮图标样式新增，播放器设置界面重新整理分组和控件排版",
                "主页、音乐库、我的、设置页增加 iPad 最大宽度适配",
                "播放列表、最近播放和日志界面背景同步主页壁纸"
            ],
            fixes: [
                "修复 QQ 音乐喜欢列表不显示的问题",
                "修复最近播放、日志、本地歌单和播放列表不同步主页壁纸的问题",
                "修复设置页掉帧问题；如果本次仍然掉帧，建议更换设备",
                "修复 iOS 15 编译兼容问题"
            ]
        ),
        VersionLog(
            id: "1.5.6",
            version: "1.5.6",
            title: "控制面板与播放器体验优化",
            features: [
                "新增控制面板封面页样式，整合封面、预览歌词与常用操作",
                "控制中心封面页改为液态玻璃效果，并缩小上移",
                "自定义布局新增控制中心整体、封面、标题、歌词和按钮组件，默认位置优化为控中标题 y=3、控中歌词 y=4、控中按钮 y=12",
                "封面页歌名、歌手和预览歌词支持渐变、高光及高光强度调节",
                "播放页背景浮尘新增开关，默认关闭；动态浮尘支持密度和大小调节",
                "全局上传壁纸自动同步到播放器封面页和控制中心背景",
                "播放页支持从顶部下划关闭，并加入缩放、淡出动画"
            ],
            fixes: [
                "修复酷狗排行榜歌曲封面缺失或未归一化的问题",
                "提高内置音源搜索上限",
                "播放器设置打开后不再默认展开播放和歌词显示分组"
            ]
        ),
        VersionLog(
            id: "1.5.5",
            version: "1.5.5",
            title: "播放流畅度与发热优化",
            notices: [
                "从 1.5.4 版本开始，播放器设置已从右上角删除，改为点击中间歌曲正在播放的标题打开。"
            ],
            features: [
                "优化播放中全局刷新策略，移除高刷保持器的常驻空转刷新，降低设置页、我的页面和播放器页面的发热与掉帧",
                "本地壁纸、歌词背景、设置页缩略图改为复用解码缓存，减少滚动和切换设置时的重复图片解码",
                "锁屏/系统正在播放封面增加缓存，避免播放状态变化时反复下载和刷新同一张封面",
                "聆澜内置音源支持多密钥池，当前密钥未命中时自动切换下一个，并记住最近可用密钥",
                "播放器设置新增封面页歌名、歌手、预览歌词与未播放歌词颜色调节",
                "封面页新增控制面板样式，将封面、预览歌词、收藏、评论、下载和更多操作整合到同一张高级面板"
            ],
            fixes: [
                "修复播放中进度更新过于频繁导致非播放器页面也跟随重绘的问题",
                "修复重新上传歌词背景或恢复壁纸后，部分位置可能继续显示旧图片缓存的问题",
                "修复酷狗排行榜详情歌曲封面链接未归一化，并在官网榜单缺封面时自动用移动端榜单数据补齐封面",
                "优化巨魔安装场景下播放中切换页面的刷新与解码负担"
            ]
        ),
        VersionLog(
            id: "1.5.4",
            version: "1.5.4",
            title: "歌手主页与播放列表体验修复",
            features: [
                "歌手主页背景同步主页壁纸"
            ],
            fixes: [
                "修复长歌名撑宽歌曲列表布局的问题，统一使用有限宽度和尾部截断",
                "修复歌手主页只加载 30 首歌曲的问题，网易云和 QQ 音乐改为分页加载更多歌曲",
                "重点修复酷狗主页加载任务重复触发，导致结果无限返回和网络请求风暴的问题",
                "调整播放器底部循环按钮与播放列表按钮为左右对称默认位置，循环 x=-5、播放列表 x=5，y=0",
                "移除沉浸封面播放器及相关设置，恢复经典播放器界面"
            ]
        ),
        VersionLog(
            id: "1.5.3",
            version: "1.5.3",
            title: "备份、歌词背景与界面体验优化",
            features: [
                "完善配置备份与恢复，支持保存壁纸、字体、播放器布局、自定义音源和本地歌单等设置",
                "我的页面新增交流群入口，可直接查看群二维码",
                "歌词页面支持自定义背景图片、背景模糊，并可同步到封面播放页",
                "设置新增平台显示管理，主页、搜索、音乐库和登录入口按选择显示平台",
                "主页歌单广场支持收起和展开，播放设置支持收缩分组"
            ],
            fixes: [
                "修复壁纸备份只保存旧路径，恢复后图片不显示的问题",
                "修复排行榜详情说明区域出现白块、玻璃效果不一致的问题",
                "修复隐藏平台后部分页面仍显示该平台的问题",
                "修复自定义歌词背景导致播放器界面位置偏移的问题",
                "优化评论区、榜单详情页与播放器设置的背景显示和页面流畅度"
            ]
        ),
        VersionLog(
            id: "1.5.2",
            version: "1.5.2",
            title: "榜单详情、备份与交流群优化",
            features: [
                "备份功能覆盖更多已调试设置，包含壁纸、字体、播放器布局、自定义音源、本地歌单等本机配置",
                "我的页面底部新增“交流群”入口，点击后可直接查看群二维码",
                "榜单详情页顶部信息卡恢复与应用整体一致的通透卡片效果",
                "首次引导页新增平台选择，可按需要只显示部分平台",
                "设置页新增“平台显示”，可随时重新选择需要展示的平台",
                "主页歌单广场新增收缩/展开，默认收起减少首页长度",
                "播放器歌词界面支持上传自定义背景图，并可调节背景模糊强度",
            ],
            fixes: [
                "修复打开任意排行榜详情后，榜单说明区域出现白块背景的问题",
                "修复备份导出范围不完整的问题，同时排除账号登录信息、搜索记录和日志",
                "修复壁纸备份只保存旧沙盒路径、没有补齐图片内容，导致恢复后壁纸丢失的问题",
                "修复隐藏某个平台后，主页、搜索、音乐库、账号登录等入口仍显示该平台的问题",
                "修复恢复备份时可能写回隐私记录或运行态标记的问题",
            ]
        ),
        VersionLog(
            id: "1.5.1",
            version: "1.5.1",
            title: "流畅度、备份与个性化优化",
            features: [
                "播放进度刷新拆分为独立时钟，播放中浏览主页、搜索、音乐库、我的页面更流畅",
                "播放器设置改为全屏打开，打开后暂停播放器页面 UI 渲染但保持歌曲继续播放",
                "播放器设置支持收缩分组、紧凑布局和稳定通透卡片",
                "新增全局主文字颜色自定义，作用于搜索、歌单、我的、设置等页面",
                "每日推荐、排行榜、QQ 歌单详情新增搜索与随机播放",
                "壁纸背景同步到更多设置页、歌单、排行榜和每日推荐详情",
            ],
            fixes: [
                "修复播放中滑动主页排行榜、打开设置时明显卡顿发热的问题",
                "修复播放器右上角更多菜单和播放器设置内部分控件偶发需要点多次的问题",
                "修复排行榜板块在自定义壁纸下出现大块白底的问题",
                "恢复主页排行榜板块的通透卡片质感",
                "备份与恢复已跳过账号 cookie、token 和用户资料",
                "删除设置页导入日志入口，并将导出日志移入查看日志菜单",
            ]
        ),
        VersionLog(
            id: "1.5.0",
            version: "1.5.0",
            title: "酷狗音乐与更新体验优化",
            features: [
                "优化酷狗音乐相关功能，改善搜索、歌单同步与播放链路",
                "内置音源无需登录账号即可尝试播放大部分会员歌曲",
                "支持自定义导入音源，作为官方播放地址不可用时的备用来源",
                "简化「我的」界面布局，减少不必要的入口和层级",
                "新增 GitHub 自动检测更新功能，并在发现新版本时显示更新内容",
                "更新弹窗支持直接下载最新版 IPA，完成后自动呼出系统分享面板",
            ],
            fixes: [
                "优化第三方音源匹配与播放地址解析",
                "优化设置页面滚动、页面切换及相关交互的流畅度",
                "修复部分更新提醒和版本说明显示问题",
            ]
        ),
        VersionLog(
            id: "1.4.0",
            version: "1.4.0",
            title: "酷狗歌单同步测试与歌词同步修复",
            features: [
                "音乐库新增酷狗账号扫码登录与云端歌单同步测试入口",
                "酷狗同步改用移动端 token、设备注册、mid/dfid 与网关签名流程",
                "酷狗歌单歌曲支持读取 hash、album audio id 并尝试官方播放地址解析",
            ],
            fixes: [
                "歌词进度刷新由 1 秒提升到 0.2 秒，减少所有平台歌词慢半拍或跳行的问题",
                "切歌时歌词加载加入歌曲校验，避免旧歌曲歌词请求返回后覆盖当前歌曲",
                "酷狗只保留账号与歌单同步入口，不加回主页排行榜和搜索入口",
            ]
        )
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
    @State private var remoteLog: VersionLog?

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: ThemeStore.shared.backgroundSyncAll ? ThemeStore.shared.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let remoteLog {
                            VersionLogCard(log: remoteLog)
                        }
                        ForEach(ChangelogStore.logs.filter { log in
                            guard let remoteLog else { return true }
                            return log.version != remoteLog.version
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
            remoteLog = await ChangelogStore.fetchRemoteLatest()
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
                    .foregroundStyle(Color.beansLabel)
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
            Text(title)
                .font(BeansFont.appFont(14, .bold))
                .foregroundStyle(Color.beansAmber)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.beansAmber)
                        .padding(.top, 2)
                    Text(item)
                        .font(BeansFont.appFont(13))
                        .foregroundStyle(Color.beansLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - 软件使用说明

struct UsageGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(title: String, icon: String, lines: [String])] = [
        (
            "应用简介",
            "music.note.house.fill",
            ["Beans Music 是一款聚合网易云音乐、QQ 音乐与酷狗音乐歌单同步能力的第三方音乐播放器客户端，仅供个人学习研究使用。"]
        ),
        (
            "多平台切换",
            "arrow.left.arrow.right",
            ["首页和搜索保留网易云 / QQ 音乐入口；音乐库可同步网易云、QQ 音乐与酷狗云端歌单。"]
        ),
        (
            "账号服务",
            "person.crop.circle.badge.checkmark",
            ["「我的」页面可统一管理账号登录。登录后会同步对应平台歌单与账号状态。"]
        ),
        (
            "播放体验",
            "play.circle.fill",
            ["全屏播放器支持歌词、进度跳转、倍速、定时关闭、循环模式与音质选择。歌词不同步时可在播放器设置中微调偏移。"]
        ),
        (
            "个性化定制",
            "paintpalette.fill",
            ["支持自定义壁纸、主题色、歌词样式与底部布局。"]
        )
    ]

    var body: some View {
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: ThemeStore.shared.backgroundSyncAll ? ThemeStore.shared.customBackground : nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: section.icon)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.beansAmber)
                                    Text(section.title)
                                        .font(BeansFont.appFont(14, .bold))
                                        .foregroundStyle(Color.beansLabel)
                                }
                                ForEach(section.lines, id: \.self) { line in
                                    Text(line)
                                        .font(BeansFont.appFont(12.5))
                                        .foregroundStyle(Color.beansLabel.opacity(0.85))
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                BeansGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .beansCardShadow(radius: 8, y: 3)
                        }
                        Text("Beans Music · 仅供学习交流 · 音乐版权归各平台所有 · 酷狗音乐名称及图标归酷狗音乐 / 腾讯音乐娱乐相关权利方所有")
                            .font(BeansFont.appFont(11))
                            .foregroundStyle(Color.beansComment.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(16)
                }
                .beansScrollIndicatorsHidden()
            }
            .navigationTitle("软件使用说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(BeansSheetModifier(detents: [.large]))
    }
}
