import SwiftUI

/// 编辑当前平台云端歌单的显示顺序。排序只影响本地展示，不会改动平台服务器上的歌单。
struct SyncedPlaylistOrderSheet: View {
    let title: String
    let source: SongSource
    @Binding var playlists: [Playlist]

    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .active

    var body: some View {
        BeansNavigationStack {
            List {
                if playlists.isEmpty {
                    EmptyStateView(icon: "music.note.list", text: "暂无可排序的云端歌单")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(playlists) { playlist in
                        HStack(spacing: 12) {
                            CoverImage(url: playlist.coverURL, size: 44, cornerRadius: 10)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(playlist.name)
                                    .font(BeansFont.appFont(15, .medium))
                                    .foregroundStyle(Color.beansLabel)
                                    .lineLimit(1)
                                Text(beansSongCountText(playlist.trackCount))
                                    .font(BeansFont.appFont(12))
                                    .foregroundStyle(Color.beansComment)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onMove { offsets, destination in
                        var reordered = playlists
                        reordered.move(fromOffsets: offsets, toOffset: destination)
                        playlists = reordered
                        SyncedPlaylistOrderStore.shared.save(reordered, source: source)
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .listStyle(.plain)
            .beansScrollContentBackgroundHidden()
            .background {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
