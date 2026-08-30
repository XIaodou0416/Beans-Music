import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            ZStack {
                GlassBackdrop(customColor: theme.backgroundSyncAll ? theme.customBackground : nil)
                if player.queue.isEmpty {
                    EmptyStateView(icon: "music.note.list", text: "播放队列为空")
                } else {
                    List {
                        Section("接下来 (\(player.queue.count) 首)") {
                            ForEach(Array(player.queue.enumerated()), id: \.element.identityKey) { index, song in
                                row(song, index: index)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                            .onDelete { offsets in
                                let indices = offsets.map { $0 }
                                for index in indices.sorted(by: >) where player.queue.indices.contains(index) {
                                    player.removeFromQueue(at: index)
                                }
                            }
                        }
                    }
                    .beansScrollContentBackgroundHidden()
                    .listStyle(.plain)
                }
            }
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            player.clearQueue()
                        } label: {
                            Label("清空队列", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .background {
            HighRefreshConfigurator()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func row(_ song: Song, index: Int) -> some View {
        let isCurrent = index == player.currentIndex
        HStack(spacing: 12) {
            CoverImage(url: song.coverURL, size: 42, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.name)
                    .font(BeansFont.appFont(15, isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.beansAmber : Color.beansLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Text(song.artists)
                    .font(BeansFont.appFont(12))
                    .foregroundStyle(Color.beansComment)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            if isCurrent {
                if player.isPlaying {
                    NowPlayingIndicator()
                } else {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.beansAmber)
                }
            } else {
                Text(song.formattedDuration)
                    .font(BeansFont.appFont(12, .regular, .monospaced))
                    .foregroundStyle(Color.beansComment)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background {
                        BeansGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .onTapGesture {
            if player.queue.indices.contains(index) {
                player.playQueueIndex(index)
            }
        }
    }
}
