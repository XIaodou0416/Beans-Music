import SwiftUI

struct ResourceCacheLimitSection: View {
    @Binding var isCacheLimitEnabled: Bool
    @Binding var cacheLimitMegabytes: Int
    let applyLimit: () -> Void

    var body: some View {
        Section {
            Toggle("启用缓存上限", isOn: $isCacheLimitEnabled)

            Picker(selection: $cacheLimitMegabytes) {
                ForEach(ResourceCacheLimitSettings.limitMegabytePresets, id: \.self) { megabytes in
                    Text(ResourceCacheByteFormatter.megabytes(megabytes))
                        .tag(megabytes)
                }
            } label: {
                MineSettingsLabel("缓存上限", systemImage: "internaldrive")
            }
            .pickerStyle(.menu)
            .disabled(!isCacheLimitEnabled)

            Button(action: applyLimit) {
                MineSettingsLabel("立即应用上限", systemImage: "gauge.with.dots.needle.50percent")
            }
            .disabled(!isCacheLimitEnabled)
        } header: {
            Text("缓存上限")
        } footer: {
            Text("超过上限时会自动优先清理视频分片和图片磁盘缓存，再清理 API、字幕/弹幕等可重新获取的缓存。")
        }
    }
}
