import SwiftUI

/// 经典播放器使用的原始播放队列列表。
struct QueueView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @AppStorage("beans.queueOverlayPresented") private var queueOverlayPresented = false
    @State private var draggingIndex: Int?
    @State private var dragStartIndex: Int?

    private let rowStep: CGFloat = 76

    var body: some View {
        let _ = theme.accent
        BeansNavigationStack {
            Group {
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
                                for index in offsets.sorted(by: >) where player.queue.indices.contains(index) {
                                    player.removeFromQueue(at: index)
                                }
                            }
                        }
                    }
                    .beansScrollContentBackgroundHidden()
                    .listStyle(.plain)
                    .background(LinearGradient.beansBackdrop)
                }
            }
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
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
        .onAppear { queueOverlayPresented = true }
        .onDisappear { queueOverlayPresented = false }
    }

    private func row(_ song: Song, index: Int) -> some View {
        let isCurrent = index == player.currentIndex
        return HStack(spacing: 10) {
            Button {
                guard player.queue.indices.contains(index) else { return }
                player.playQueueIndex(index)
            } label: {
                HStack(spacing: 12) {
                    CoverImage(url: song.coverURL, song: song, size: 42, cornerRadius: 9)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.name)
                            .font(BeansFont.appFont(15, isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? Color.beansAmber : Color.beansLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(song.artists)
                            .font(BeansFont.appFont(12))
                            .foregroundStyle(Color.beansComment)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            QueueReorderHandle(
                position: index,
                maxPosition: max(player.queue.count - 1, 0),
                rowStep: rowStep,
                activePosition: $draggingIndex,
                startPosition: $dragStartIndex
            ) { source, destination in
                player.moveQueueItem(from: source, to: destination)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background {
            BeansGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .contextMenu {
            Button(role: .destructive) {
                player.removeFromQueue(at: index)
            } label: {
                Label("移除", systemImage: "trash")
            }
        }
    }
}

/// 只允许从右侧手柄开始排序，避免整行点击和多个歌曲同时响应拖动。
struct QueueReorderHandle: View {
    let position: Int
    let maxPosition: Int
    let rowStep: CGFloat
    @Binding var activePosition: Int?
    @Binding var startPosition: Int?
    let onMove: (Int, Int) -> Void

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.beansComment.opacity(0.78))
            .frame(width: 38, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("长按并拖动调整顺序")
            .gesture(queueDragGesture)
    }

    private var queueDragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.34)
            .sequenced(before: DragGesture(minimumDistance: 2))
            .onChanged { value in
                switch value {
                case .first(true):
                    if activePosition == nil {
                        activePosition = position
                        startPosition = position
                        BeansHaptics.medium()
                    }
                case .second(true, let drag?):
                    guard let start = startPosition, let current = activePosition else { return }
                    let target = min(
                        max(start + Int((drag.translation.height / rowStep).rounded()), 0),
                        maxPosition
                    )
                    if target != current {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            onMove(current, target)
                        }
                        activePosition = target
                        BeansHaptics.tap()
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                activePosition = nil
                startPosition = nil
            }
    }
}
