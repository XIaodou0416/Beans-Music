import Foundation
import SwiftUI
import UIKit
import WidgetKit

private let widgetGroupID = "group.com.beans.music"
private let widgetStateKey = "beans.widget.playback.state"

private struct WidgetPlaybackState: Codable {
    let songKey: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let progress: Double
    let isPlaying: Bool
    let coverFileName: String?
    let colorHex: String?
    let updatedAt: Date
}

private struct BeansWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let progress: Double
    let isPlaying: Bool
    let cover: UIImage?
    let accent: Color
}

private struct BeansWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BeansWidgetEntry {
        BeansWidgetEntry(
            date: Date(),
            title: "正在播放",
            artist: "Beans Music",
            album: "",
            duration: 240,
            progress: 0,
            isPlaying: false,
            cover: nil,
            accent: Color(red: 0.88, green: 0.12, blue: 0.14)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BeansWidgetEntry) -> Void) {
        completion(makeEntry(date: Date(), state: readState()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BeansWidgetEntry>) -> Void) {
        let now = Date()
        guard let state = readState() else {
            completion(Timeline(entries: [placeholder(in: context)], policy: .after(now.addingTimeInterval(900))))
            return
        }

        let entries = (0..<24).map { index in
            let date = now.addingTimeInterval(Double(index) * 15)
            let elapsed = state.isPlaying ? Double(index) * 15 : 0
            let progress = min(max(state.progress + elapsed, 0), max(state.duration, 0))
            return makeEntry(date: date, state: state, progress: progress)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(360))))
    }

    private func readState() -> WidgetPlaybackState? {
        guard let defaults = UserDefaults(suiteName: widgetGroupID),
              let data = defaults.data(forKey: widgetStateKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetPlaybackState.self, from: data)
    }

    private func makeEntry(
        date: Date,
        state: WidgetPlaybackState?,
        progress: Double? = nil
    ) -> BeansWidgetEntry {
        guard let state else {
            return BeansWidgetEntry(
                date: date,
                title: "正在播放",
                artist: "Beans Music",
                album: "",
                duration: 240,
                progress: 0,
                isPlaying: false,
                cover: nil,
                accent: Color(red: 0.88, green: 0.12, blue: 0.14)
            )
        }

        return BeansWidgetEntry(
            date: date,
            title: state.title,
            artist: state.artist,
            album: state.album,
            duration: max(state.duration, 0),
            progress: max(progress ?? state.progress, 0),
            isPlaying: state.isPlaying,
            cover: loadCover(fileName: state.coverFileName),
            accent: color(from: state.colorHex)
        )
    }

    private func loadCover(fileName: String?) -> UIImage? {
        guard let fileName,
              let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: widgetGroupID
              ) else {
            return nil
        }
        return UIImage(contentsOfFile: container.appendingPathComponent(fileName).path)
    }

    private func color(from hex: String?) -> Color {
        guard let hex, hex.count == 6, let value = Int(hex, radix: 16) else {
            return Color(red: 0.88, green: 0.12, blue: 0.14)
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private struct BeansWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: BeansWidgetEntry

    private var primary: Color { colorScheme == .dark ? .white : .black }
    private var secondary: Color { primary.opacity(colorScheme == .dark ? 0.66 : 0.54) }
    private var progressFraction: CGFloat {
        guard entry.duration > 0 else { return 0 }
        return CGFloat(min(max(entry.progress / entry.duration, 0), 1))
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
        .modifier(WidgetContainerBackground(accent: entry.accent, colorScheme: colorScheme))
    }
}

private extension BeansWidgetView {
    var cover: some View {
        Group {
            if let image = entry.cover {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [entry.accent, entry.accent.opacity(0.46), .black.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 0.7)
        }
    }

    var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(primary)
                .lineLimit(1)
            Text(entry.artist)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondary)
                .lineLimit(1)
        }
    }

    var progressLine: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(primary.opacity(0.14))
                Capsule()
                    .fill(entry.accent)
                    .frame(width: proxy.size.width * progressFraction)
            }
        }
        .frame(height: 3)
    }

    var playLink: some View {
        Link(destination: URL(string: "beansmusic://widget/playPause")!) {
            Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(entry.accent, in: Circle())
        }
    }

    var previousLink: some View {
        Link(destination: URL(string: "beansmusic://widget/previous")!) {
            Image(systemName: "backward.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primary.opacity(0.76))
                .frame(width: 30, height: 30)
        }
    }

    var nextLink: some View {
        Link(destination: URL(string: "beansmusic://widget/next")!) {
            Image(systemName: "forward.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primary.opacity(0.76))
                .frame(width: 30, height: 30)
        }
    }

    var smallLayout: some View {
        ZStack(alignment: .bottomLeading) {
            cover
            LinearGradient(
                colors: [.clear, .black.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 7) {
                Spacer(minLength: 0)
                titleBlock
                HStack {
                    Text(entry.isPlaying ? "正在播放" : "已暂停")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    playLink
                }
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    var mediumLayout: some View {
        HStack(spacing: 12) {
            Link(destination: URL(string: "beansmusic://widget/open")!) {
                cover.frame(width: 78, height: 78)
            }

            VStack(alignment: .leading, spacing: 7) {
                titleBlock
                Text(entry.album.isEmpty ? "正在播放" : entry.album)
                    .font(.system(size: 11))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                progressLine
            }

            VStack(spacing: 4) {
                playLink
                HStack(spacing: 0) {
                    previousLink
                    nextLink
                }
            }
        }
        .padding(14)
    }

    var largeLayout: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 6) {
                Image(systemName: entry.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(entry.accent)
                Text("BEANS MUSIC")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(secondary)
                Spacer()
                Link(destination: URL(string: "beansmusic://widget/open")!) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(secondary)
                }
            }

            HStack(spacing: 14) {
                Link(destination: URL(string: "beansmusic://widget/open")!) {
                    cover.frame(width: 108, height: 108)
                }
                VStack(alignment: .leading, spacing: 6) {
                    titleBlock
                    Text(entry.album.isEmpty ? "正在播放" : entry.album)
                        .font(.system(size: 11))
                        .foregroundStyle(secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(entry.isPlaying ? "正在播放" : "已暂停")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(entry.accent)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 5) {
                progressLine
                HStack {
                    Text(formatTime(entry.progress))
                    Spacer()
                    Text(formatTime(entry.duration))
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(secondary)
            }

            HStack {
                previousLink
                Spacer()
                playLink
                Spacer()
                nextLink
            }
        }
        .padding(16)
    }

    func formatTime(_ value: Double) -> String {
        let total = max(0, Int(value))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct WidgetContainerBackground: ViewModifier {
    let accent: Color
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        let background = LinearGradient(
            colors: [
                accent.opacity(colorScheme == .dark ? 0.36 : 0.12),
                accent.opacity(colorScheme == .dark ? 0.12 : 0.04),
                colorScheme == .dark ? Color.black.opacity(0.96) : Color.white.opacity(0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        if #available(iOSApplicationExtension 17.0, *) {
            content
                .background(background)
                .containerBackground(for: .widget) { background }
        } else {
            content.background(background)
        }
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
