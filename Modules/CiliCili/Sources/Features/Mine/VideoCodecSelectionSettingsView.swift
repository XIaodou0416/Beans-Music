import SwiftUI

struct VideoCodecSelectionSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var codecOrder: [VideoCodecFamily]

    init(libraryStore: LibraryStore) {
        self.libraryStore = libraryStore
        _codecOrder = State(initialValue: libraryStore.videoCodecPreference.codecOrder)
    }

    var body: some View {
        List {
            Section {
                ForEach(codecOrder) { codec in
                    MineSettingsLabel(codec.title, systemImage: codec.systemImage)
                }
                .onMove(perform: moveCodecs)
            } header: {
                Text("自动选择顺序")
            } footer: {
                Text("从上到下尝试；视频没有前一种编码时，自动使用下一种。长按右侧拖动排序。")
            }

            Section {
                ForEach(VideoCodecFamily.configurableCases) { codec in
                    Toggle(isOn: binding(for: codec)) {
                        VStack(alignment: .leading, spacing: 3) {
                            MineSettingsLabel(codec.title, systemImage: codec.systemImage)
                            Text(codec.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!codec.isAvailableOnCurrentDevice || (codecOrder.count == 1 && codecOrder.contains(codec)))
                }
            } header: {
                Text("启用编码")
            } footer: {
                Text("关闭后不会请求或选择该编码。为保证视频可以播放，至少需要保留一种。")
            }
        }
        .environment(\.editMode, .constant(.active))
        .tint(libraryStore.appTintColor)
        .listStyle(.insetGrouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .onChange(of: libraryStore.videoCodecPreference) { _, preference in
            if preference.codecOrder != codecOrder {
                codecOrder = preference.codecOrder
            }
        }
    }

    private func binding(for codec: VideoCodecFamily) -> Binding<Bool> {
        Binding(
            get: { codecOrder.contains(codec) },
            set: { isEnabled in
                if isEnabled {
                    guard !codecOrder.contains(codec) else { return }
                    codecOrder.append(codec)
                } else {
                    guard codecOrder.count > 1 else { return }
                    codecOrder.removeAll { $0 == codec }
                }
                commit()
            }
        )
    }

    private func moveCodecs(from offsets: IndexSet, to destination: Int) {
        codecOrder.move(fromOffsets: offsets, toOffset: destination)
        commit()
    }

    private func commit() {
        libraryStore.setVideoCodecPreference(VideoCodecPreference(codecOrder: codecOrder))
    }
}
