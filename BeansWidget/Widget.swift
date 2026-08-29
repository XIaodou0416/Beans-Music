import ActivityKit
import SwiftUI
import WidgetKit

/// 锁屏和灵动岛展开区的正在播放视图。
@available(iOS 16.1, *)
struct NowPlayingActivityView: View {
    let context: ActivityViewContext<NowPlayingAttributes>

    @ViewBuilder
    private var cover: some View {
        if let urlString = context.state.coverURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.gray.opacity(0.25))
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }

    var body: some View {
        HStack(spacing: 12) {
            cover
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.songName)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.lyricText.isEmpty ? context.state.artist : context.state.lyricText)
                    .font(.caption)
                    .foregroundStyle(context.state.lyricText.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                ProgressView(value: context.state.duration > 0 ? min(context.state.progress / context.state.duration, 1) : 0)
                    .tint(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .activityBackgroundTint(.black.opacity(0.7))
        .activitySystemActionForegroundColor(.white)
    }
}

/// 灵动岛实时活动。
@available(iOS 16.1, *)
struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            NowPlayingActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        cover(in: context)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.songName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(context.state.lyricText.isEmpty ? context.state.artist : context.state.lyricText)
                                .font(.caption)
                                .foregroundStyle(context.state.lyricText.isEmpty ? .secondary : .primary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.duration > 0 ? min(context.state.progress / context.state.duration, 1) : 0)
                        .tint(.secondary)
                        .padding(.horizontal, 8)
                }
            } compactLeading: {
                cover(in: context)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
            } minimal: {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    @ViewBuilder
    private func cover(in context: ActivityViewContext<NowPlayingAttributes>) -> some View {
        if let urlString = context.state.coverURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.gray.opacity(0.3))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }
}

@main
struct BeansWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            NowPlayingLiveActivity()
        }
    }
}
