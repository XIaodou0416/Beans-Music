import SwiftUI
import WidgetKit

private struct BeansWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
}

private struct BeansWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BeansWidgetEntry {
        BeansWidgetEntry(
            date: Date(),
            title: "正在播放",
            artist: "Beans Music",
            album: "",
            isPlaying: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BeansWidgetEntry) -> Void) {
        completion(sampleEntry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BeansWidgetEntry>) -> Void) {
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [sampleEntry], policy: .after(refreshDate)))
    }

    private var sampleEntry: BeansWidgetEntry {
        BeansWidgetEntry(
            date: Date(),
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            isPlaying: true
        )
    }
}

private struct BeansWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BeansWidgetEntry

    var body: some View {
        widgetLayout
    }

    @ViewBuilder
    private var widgetLayout: some View {
        Group {
            switch family {
            case .systemSmall:
                smallLayout
            case .systemLarge:
                largeLayout
            default:
                mediumLayout
            }
        }
        .modifier(BeansWidgetBackground())
    }
}

private struct BeansWidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) {
                Color.black
            }
        } else {
            content.background(Color.black)
        }
    }
}

private extension BeansWidgetView {
    var cover: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.96, green: 0.18, blue: 0.16), Color(red: 0.28, green: 0.03, blue: 0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var songText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(entry.artist)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        }
    }

    private var playButton: some View {
        Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 34, height: 34)
            .background(.white, in: Circle())
    }

    private var smallLayout: some View {
        ZStack(alignment: .bottomLeading) {
            cover
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                songText
                HStack {
                    Text("BEANS MUSIC")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.62))
                    Spacer()
                    playButton
                }
            }
            .padding(12)
        }
    }

    private var mediumLayout: some View {
        HStack(spacing: 14) {
            cover
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 10) {
                songText
                Text(entry.album)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                HStack(spacing: 18) {
                    Image(systemName: "backward.fill")
                    playButton
                    Image(systemName: "forward.fill")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("BEANS MUSIC", systemImage: "waveform")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundStyle(.white.opacity(0.62))
            }
            HStack(spacing: 14) {
                cover
                    .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 6) {
                    songText
                    Text(entry.album)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 5) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white)
                            .frame(width: 78, height: 3)
                    }
                HStack {
                    Text("1:24")
                    Spacer()
                    Text("4:03")
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
            }
            HStack {
                Image(systemName: "shuffle")
                Spacer()
                Image(systemName: "backward.fill")
                playButton
                Image(systemName: "forward.fill")
                Spacer()
                Image(systemName: "repeat")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
        }
        .padding(16)
    }
}

struct BeansWidget: Widget {
    let kind = "BeansWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BeansWidgetProvider()) { entry in
            BeansWidgetView(entry: entry)
        }
        .configurationDisplayName("Beans Music")
        .description("查看当前播放歌曲")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct BeansWidgetBundle: WidgetBundle {
    var body: some Widget {
        BeansWidget()
    }
}
