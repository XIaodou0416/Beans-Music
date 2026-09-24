import SwiftUI

struct MinePrivacySettingsView: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { libraryStore.incognitoModeEnabled },
                    set: { libraryStore.setIncognitoModeEnabled($0) }
                )) {
                    MineSettingsLabel("无痕模式", systemImage: "eye.slash")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.guestModeEnabled },
                    set: { libraryStore.setGuestModeEnabled($0) }
                )) {
                    MineSettingsLabel("游客推荐模式", systemImage: "person.crop.circle.badge.questionmark")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.multiAccountExperimentEnabled },
                    set: { libraryStore.setMultiAccountExperimentEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        MineSettingsLabel("多账号用途分配实验", systemImage: "person.2.badge.gearshape")

                        Text("开着后可以保存多个账号，并单独指定主账号、视频取流账号、动态页取流账号、点赞投币收藏账号和观看记录账号。关掉后所有功能继续使用主账号，不会删除已经保存的账号。")
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("无痕模式下播放取流仍使用账号信息，但不会上报观看进度到云端历史。游客推荐模式只影响首页推荐：开启后按未登录状态请求，不使用账号画像；关闭后 App 端推荐会带登录状态请求。点赞、投币、收藏、关注等账号操作不受影响。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }
}
