import SwiftUI

// MARK: - 板块自定义排序（音乐库 / 主页等页面板块顺序可拖动调整并持久化）

enum SectionOrderStore {
    static let libraryKey = "beans.library.sectionOrder"
    static let homeKey = "beans.home.sectionOrder"
    static let profileKey = "beans.profile.sectionOrder"

    /// 音乐库板块默认顺序
    static let libraryDefaults = ["我的歌单", "最近播放", "本地音乐库"]
    /// 主页板块默认顺序
    static let homeDefaults = ["每日推荐", "排行榜", "歌单广场"]
    /// 我的界面板块默认顺序
    static let profileDefaults = ["账号", "关于"]

    /// 读取已保存顺序：自动补全新板块、剔除已废弃板块
    static func load(_ key: String, defaults: [String]) -> [String] {
        var order = UserDefaults.standard.stringArray(forKey: key) ?? defaults
        if key == libraryKey, order == ["本地音乐库", "我的歌单", "最近播放"] {
            order = libraryDefaults
        }
        if key == profileKey {
            let removed = ["我的功能", "使用说明"]
            order.removeAll { removed.contains($0) }
            if order.isEmpty { order = defaults }
        }
        for item in defaults where !order.contains(item) { order.append(item) }
        order = order.filter { defaults.contains($0) }
        if order.isEmpty { order = defaults }
        return order
    }

    static func save(_ key: String, _ order: [String]) {
        UserDefaults.standard.set(order, forKey: key)
    }
}

/// 板块排序编辑器：List 常驻编辑模式，拖动调整上下位置
struct SectionOrderSheet: View {
    let title: String
    /// 全部可用板块名（用于补全新板块）
    let sections: [String]
    @Binding var order: [String]
    var platformOrder: Binding<[String]>? = nil
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = theme.accent
        Group {
            if #available(iOS 16.0, *) {
                listView
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            } else {
                listView
            }
        }
        .onAppear {
            var merged = order
            for name in sections where !merged.contains(name) { merged.append(name) }
            merged = merged.filter { sections.contains($0) }
            if merged != order { order = merged }
        }
    }

    private var listView: some View {
        BeansNavigationStack {
            List {
                Section("页面板块") {
                    ForEach(order, id: \.self) { name in
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.beansComment.opacity(0.55))
                            Text(name)
                                .font(BeansFont.appFont(15))
                                .foregroundStyle(Color.beansLabel)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                    }
                    .onMove { from, to in
                        withAnimation(.default) {
                            order.move(fromOffsets: from, toOffset: to)
                        }
                    }
                }

                if let platformOrder {
                    Section("平台同步歌单顺序（所有界面同步）") {
                        ForEach(platformOrder.wrappedValue, id: \.self) { rawValue in
                            HStack(spacing: 12) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.beansComment.opacity(0.55))
                                Text(LocalizedStringKey(rawValue))
                                    .font(BeansFont.appFont(15))
                                    .foregroundStyle(Color.beansLabel)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.clear)
                        }
                        .onMove { from, to in
                            PlatformPreferenceStore.shared.moveProviders(from: from, to: to)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .listStyle(.plain)
            .beansScrollContentBackgroundHidden()
            .background {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("恢复默认") {
                        withAnimation(.default) {
                            order = sections
                            if let platformOrder {
                                PlatformPreferenceStore.shared.resetOrder()
                                platformOrder.wrappedValue = SearchProvider.allCases.map(\.rawValue)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
