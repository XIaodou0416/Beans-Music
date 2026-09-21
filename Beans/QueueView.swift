import SwiftUI

/// 经典播放器使用的原始播放队列列表。
struct QueueView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: PlayerManager
    @AppStorage("beans.queueOverlayPresented") private var queueOverlayPresented = false
    @State private var draggingIndex: Int?
    @State private var dragStartIndex: Int?
    @State private var dragResidual: CGFloat = 0

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
        let isDragging = draggingIndex == index
        return Button {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background {
                BeansGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .buttonStyle(GlassPressButtonStyle(scale: 0.985))
        .scaleEffect(isDragging ? 1.025 : 1)
        .offset(y: isDragging ? dragResidual : 0)
        .zIndex(isDragging ? 10 : 0)
        .shadow(
            color: isDragging ? .black.opacity(0.22) : .clear,
            radius: isDragging ? 16 : 0,
            y: isDragging ? 8 : 0
        )
        .blur(radius: draggingIndex != nil && !isDragging ? 1.15 : 0)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.82), value: draggingIndex)
        .simultaneousGesture(queueDragGesture(for: index))
        .contextMenu {
            Button(role: .destructive) {
                player.removeFromQueue(at: index)
            } label: {
                Label("移除", systemImage: "trash")
            }
        }
    }

    private func queueDragGesture(for index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.34)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    if draggingIndex == nil {
                        draggingIndex = index
                        dragStartIndex = index
                        dragResidual = 0
                        BeansHaptics.medium()
                    }
                case .second(true, let drag):
                    guard let start = dragStartIndex,
                          let current = draggingIndex,
                          player.queue.indices.contains(current) else { return }
                    let target = min(
                        max(start + Int((drag.translation.height / rowStep).rounded()), 0),
                        max(player.queue.count - 1, 0)
                    )
                    if target != current {
                        player.moveQueueItem(from: current, to: target)
                        draggingIndex = target
                        BeansHaptics.tap()
                    }
                    dragResidual = drag.translation.height - CGFloat(target - start) * rowStep
                default:
                    break
                }
            }
            .onEnded { _ in
                draggingIndex = nil
                dragStartIndex = nil
                dragResidual = 0
            }
    }
}
