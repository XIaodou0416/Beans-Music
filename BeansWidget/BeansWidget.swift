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
        BeansWidgetEntry(date: Date(), title: "正在播放", artist: "Beans Music", album: "", isPlaying: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (BeansWidgetEntry) -> Void) {
        completion(sampleEntry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BeansWidgetEntry>) -> Void) {
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())
            ?? Date().addingTimeInterval(900)
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
    @Environment(\.colorScheme) private var colorScheme
    let entry: BeansWidgetEntry

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.98, green: 0.34, blue: 0.34)
            : Color(red: 0.86, green: 0.09, blue: 0.11)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        primaryText.opacity(colorScheme == .dark ? 0.66 : 0.56)
    }

    var body: some View {
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
        .background(widgetBackground)
        .modifier(BeansWidgetBackground())
    }

    private var widgetBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    accent.opacity(colorScheme == .dark ? 0.42 : 0.15),
                    accent.opacity(colorScheme == .dark ? 0.15 : 0.05),
                    colorScheme == .dark ? Color.black.opacity(0.96) : Color.white.opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(accent.opacity(colorScheme == .dark ? 0.18 : 0.08))
                .frame(width: 180, height: 180)
                .blur(radius: 32)
                .offset(x: 80, y: -92)
        }
    }
}

private struct BeansWidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) {
                Color.clear
            }
        } else {
            content
        }
    }
}

private extension BeansWidgetView {
    var cover: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.95), accent.opacity(0.58), Color.black.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 9, y: 5)
    }

    var header: some View {
        HStack(spacing: 5) {
            Image(systemName: entry.isPlaying ? "waveform" : "music.note")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)

            Text("BEANS MUSIC")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(secondaryText)

            Spacer(minLength: 0)

            Circle()
                .fill(entry.isPlaying ? accent : secondaryText)
                .frame(width: 5, height: 5)
        }
    }

    var songText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(primaryText)
                .lineLimit(1)

            Text(entry.artist)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
        }
    }

    var albumText: some View {
        Text(entry.album.isEmpty ? "正在播放" : entry.album)
            .font(.system(size: 11))
            .foregroundStyle(secondaryText.opacity(0.9))
            .lineLimit(1)
    }

    var playButton: some View {
        Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 35, height: 35)
            .background(accent, in: Circle())
            .shadow(color: accent.opacity(0.28), radius: 7, y: 3)
    }

    var transportButton: some View {
        Image(systemName: "forward.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(primaryText.opacity(0.7))
            .frame(width: 30, height: 30)
            .background(primaryText.opacity(0.08), in: Circle())
    }

    var progressLine: some View {
        Capsule()
            .fill(primaryText.opacity(0.14))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(accent)
                    .frame(width: 58, height: 3)
            }
    }

    var smallLayout: some View {
        ZStack(alignment: .bottomLeading) {
            cover
            LinearGradient(
                colors: [.clear, .black.opacity(0.88)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 7) {
                Spacer(minLength: 0)
                songText
                HStack(spacing: 0) {
                    Image(systemName: entry.isPlaying ? "waveform" : "pause")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    playButton
                }
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    var mediumLayout: some View {
        HStack(spacing: 13) {
            cover
                .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 7) {
                header
                songText
                albumText
                progressLine
            }

            VStack(spacing: 7) {
                playButton
                transportButton
            }
        }
        .padding(14)
    }

    var largeLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(spacing: 15) {
                cover
                    .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 7) {
                    songText
                    albumText
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Image(systemName: entry.isPlaying ? "play.fill" : "pause.fill")
                        Text(entry.isPlaying ? "正在播放" : "已暂停")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 6) {
                progressLine
                HStack {
                    Text("1:24")
                    Spacer()
                    Text("4:03")
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
            }

            HStack {
                Image(systemName: "shuffle")
                    .foregroundStyle(secondaryText)
                Spacer()
                Image(systemName: "backward.fill")
                    .foregroundStyle(primaryText.opacity(0.72))
                playButton
                Image(systemName: "forward.fill")
                    .foregroundStyle(primaryText.opacity(0.72))
                Spacer()
                Image(systemName: "repeat")
                    .foregroundStyle(secondaryText)
            }
            .font(.system(size: 15, weight: .semibold))
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
