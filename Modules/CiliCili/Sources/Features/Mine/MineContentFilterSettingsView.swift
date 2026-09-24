import SwiftUI

struct MineContentFilterSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { libraryStore.blocksAdDynamics },
                    set: { libraryStore.setBlocksAdDynamics($0) }
                )) {
                    MineSettingsLabel("屏蔽广告动态", systemImage: "megaphone.badge.minus")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.blocksGoodsDynamics },
                    set: { libraryStore.setBlocksGoodsDynamics($0) }
                )) {
                    MineSettingsLabel("屏蔽带货动态", systemImage: "bag.badge.minus")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.blocksGoodsComments },
                    set: { libraryStore.setBlocksGoodsComments($0) }
                )) {
                    MineSettingsLabel("屏蔽带货评论", systemImage: "text.bubble.badge.minus")
                }

                NavigationLink {
                    DynamicKeywordFilterSettingsView(libraryStore: libraryStore)
                } label: {
                    PlainSettingsNavigationRow(
                        title: "自定义动态关键词",
                        subtitle: "\(libraryStore.blockedDynamicKeywords.count) 个关键词",
                    )
                }

                Text("广告动态会按常见推广关键词过滤；带货动态会按 B 站商品组件和商品元数据过滤；自定义关键词会匹配动态正文、标题和转发内容。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("推荐过滤") {
                Picker(selection: Binding(
                    get: { libraryStore.recommendMinimumDurationSeconds },
                    set: { libraryStore.setRecommendMinimumDurationSeconds($0) }
                )) {
                    ForEach(LibraryStore.supportedRecommendMinimumDurations, id: \.self) { seconds in
                        Text(recommendDurationTitle(seconds)).tag(seconds)
                    }
                } label: {
                    MineSettingsLabel("最短时长", systemImage: "timer")
                }
                .pickerStyle(.menu)

                Picker(selection: Binding(
                    get: { libraryStore.recommendMinimumViewCount },
                    set: { libraryStore.setRecommendMinimumViewCount($0) }
                )) {
                    ForEach(LibraryStore.supportedRecommendMinimumViews, id: \.self) { count in
                        Text(recommendViewTitle(count)).tag(count)
                    }
                } label: {
                    MineSettingsLabel("最低播放量", systemImage: "play.circle")
                }
                .pickerStyle(.menu)

                Picker(selection: Binding(
                    get: { libraryStore.recommendMinimumLikeRatioPercent },
                    set: { libraryStore.setRecommendMinimumLikeRatioPercent($0) }
                )) {
                    ForEach(LibraryStore.supportedRecommendMinimumLikeRatios, id: \.self) { percent in
                        Text(recommendLikeRatioTitle(percent)).tag(percent)
                    }
                } label: {
                    MineSettingsLabel("最低点赞率", systemImage: "hand.thumbsup")
                }
                .pickerStyle(.menu)

                NavigationLink {
                    RecommendKeywordFilterSettingsView(libraryStore: libraryStore)
                } label: {
                    PlainSettingsNavigationRow(
                        title: "标题关键词",
                        subtitle: "\(libraryStore.blockedRecommendKeywords.count) 个关键词",
                    )
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.appliesRecommendFiltersToRelatedVideos },
                    set: { libraryStore.setAppliesRecommendFiltersToRelatedVideos($0) }
                )) {
                    MineSettingsLabel("应用到相关推荐", systemImage: "rectangle.stack.badge.minus")
                }

                Text("默认只过滤首页推荐；打开后也会过滤视频详情页相关推荐。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }

    private func recommendDurationTitle(_ seconds: Int) -> String {
        seconds == 0 ? "不过滤" : "\(seconds) 秒"
    }

    private func recommendViewTitle(_ count: Int) -> String {
        count == 0 ? "不过滤" : "\(count)"
    }

    private func recommendLikeRatioTitle(_ percent: Int) -> String {
        percent == 0 ? "不过滤" : "\(percent)%"
    }
}
