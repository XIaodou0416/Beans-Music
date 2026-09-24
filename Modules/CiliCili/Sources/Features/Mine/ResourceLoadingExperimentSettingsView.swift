import SwiftUI

struct ResourceLoadingExperimentSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Form {
            Section("实验功能") {
                featureToggle(
                    title: "断点续播预热",
                    systemImage: "goforward",
                    isOn: Binding(
                        get: { libraryStore.resourceLoadingResumePacketWarmupEnabled },
                        set: { libraryStore.setResourceLoadingResumePacketWarmupEnabled($0) }
                    ),
                    detail: "从上次进度继续看时，多给目标片段一点准备时间，尝试减少恢复画面的等待。"
                )
            }

            Section {
                NavigationLink {
                    ResourceLoadingDiagnosticsView(libraryStore: libraryStore)
                } label: {
                    PlainSettingsNavigationRow(
                        title: "资源加载诊断",
                        subtitle: "查看命中次数、耗时和最近加载事件",
                    )
                }
            } footer: {
                Text("首屏资源优先、屏幕图片提权、重复接口合并和动态页快速恢复已作为正式功能启用。这里仍可调整断点续播预热。诊断只记录统计数字和功能状态。")
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }

    private func featureToggle(
        title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        detail: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                MineSettingsLabel(title, systemImage: systemImage)
                Text(detail)
                    .appTypography(.settingsSubtitle, fallback: .caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
