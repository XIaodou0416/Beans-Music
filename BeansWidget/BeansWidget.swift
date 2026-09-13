import Foundation
import SwiftUI
import WidgetKit
import UIKit

private let widgetGroupID = "group.com.beans.music"
private let widgetStateKey = "beans.widget.playback.state"
private let widgetCoverFileName = "beans-widget-cover.jpg"

private struct WidgetPlaybackState: Codable {
    var songKey: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var progress: Double
    var isPlaying: Bool
    var lyricRaw: String
    var coverFileName: String?
    var colorHex: String?
    var updatedAt: Date
}

private struct WidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let progress: Double
    let isPlaying: Bool
    let lyric: String
    let cover: UIImage?
    let color: Color
}

private struct BeansWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(
            date: Date(),
            title: "正在播放",
            artist: "Beans Music",
            album: "",
            duration: 240,
            progress: 64,
            isPlaying: false,
            lyric: "打开 Beans Music 开始播放",
            cover: nil,
            color: Color(red: 0.92, green: 0.12, blue: 0.12)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(makeEntry(at: Date(), state: readState()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let now = Date()
        guard let state = readState() else {
            let entry = placeholder(in: context)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(900))))
            return
        }

        let entries = (0..<24).map { index -> WidgetEntry in
            let date = now.addingTimeInterval(Double(index) * 15)
            let elapsed = state.isPlaying ? Double(index) * 15 : 0
            let progress = min(max(state.progress + elapsed, 0), max(state.duration, 0))
            return makeEntry(at: date, state: state, progress: progress)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(360))))
    }

    private func readState() -> WidgetPlaybackState? {
        guard let defaults = UserDefaults(suiteName: widgetGroupID),
              let data = defaults.data(forKey: widgetStateKey) else { return nil }
        return try? JSONDecoder().decode(WidgetPlaybackState.self, from: data)
    }

    private func makeEntry(at date: Date, state: WidgetPlaybackState?, progress: Double? = nil) -> WidgetEntry {
        guard let state else {
            return WidgetEntry(
                date: date,
                title: "正在播放",
                artist: "Beans Music",
                album: "",
                duration: 240,
                progress: 0,
                isPlaying: false,
                lyric: "打开 Beans Music 开始播放",
                cover: nil,
                color: Color(red: 0.92, green: 0.12, blue: 0.12)
            )
        }
        let cover = loadCover(fileName: state.coverFileName)
        let currentProgress = max(0, progress ?? state.progress)
        let line = currentLyric(from: state.lyricRaw, progress: currentProgress)
        return WidgetEntry(
            date: date,
            title: state.title,
            artist: state.artist,
            album: state.album,
            duration: max(0, state.duration),
            progress: currentProgress,
            isPlaying: state.isPlaying,
            lyric: line.isEmpty ? state.artist : line,
            cover: cover,
            color: color(from: state.colorHex)
        )
    }

    private func loadCover(fileName: String?) -> UIImage? {
        guard let fileName,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: widgetGroupID) else { return nil }
        return UIImage(contentsOfFile: container.appendingPathComponent(fileName).path)
    }

    private func color(from hex: String?) -> Color {
        guard let hex, hex.count == 6,
              let value = Int(hex, radix: 16) else {
            return Color(red: 0.92, green: 0.12, blue: 0.12)
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private func currentLyric(from raw: String, progress: Double) -> String {
        var result = ""
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        for line in raw.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            let text = regex.stringByReplacingMatches(in: line, options: [], range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            regex.enumerateMatches(in: line, options: [], range: range) { match, _, _ in
                guard let match,
                      let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line) else { return }
                let minutes = Double(line[minuteRange]) ?? 0
                let seconds = Double(line[secondRange]) ?? 0
                var fraction = 0.0
                if match.numberOfRanges > 3,
                   let fractionRange = Range(match.range(at: 3), in: line) {
                    let rawFraction = String(line[fractionRange])
                    fraction = (Double(rawFraction) ?? 0) / pow(10, Double(max(rawFraction.count, 1)))
                }
                if minutes * 60 + seconds + fraction <= progress {
                    result = text
                }
            }
        }
        return result
    }
}

private struct BeansWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

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
        .background(background)
        .modifier(WidgetContainerBackground())
    }

    private var background: some View {
        LinearGradient(
            colors: [
                entry.color.opacity(0.96),
                entry.color.opacity(0.48),
                Color.black.opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var cover: some View {
        if let image = entry.cover {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color.white.opacity(0.15)
                Image(systemName: "music.note")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(entry.artist)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.24))
                Capsule()
                    .fill(.white.opacity(0.95))
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 3)
    }

    private var fraction: CGFloat {
        guard entry.duration > 0 else { return 0 }
        return CGFloat(min(max(entry.progress / entry.duration, 0), 1))
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
            LinearGradient(colors: [.clear, .black.opacity(0.84)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 7) {
                Spacer()
                titleBlock
                Text(entry.lyric)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                HStack {
                    Text("BEANS MUSIC")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.62))
                    Spacer()
                    playButton
                }
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var mediumLayout: some View {
        HStack(spacing: 13) {
            cover
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 7) {
                titleBlock
                Text(entry.lyric)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                progressBar
                HStack(spacing: 16) {
                    Image(systemName: "backward.fill")
                    playButton
                    Image(systemName: "forward.fill")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("BEANS MUSIC", systemImage: "waveform")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.68))
                Spacer()
                Text(entry.isPlaying ? "正在播放" : "已暂停")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 14) {
                cover
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                VStack(alignment: .leading, spacing: 9) {
                    titleBlock
                    Text(entry.album)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                    Text(entry.lyric)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }
            }
            progressBar
            HStack {
                Image(systemName: "shuffle")
                Spacer()
                Image(systemName: "backward.fill")
                playButton
                Image(systemName: "forward.fill")
                Spacer()
                Image(systemName: "repeat")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(16)
    }
}

private struct WidgetContainerBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) { Color.clear }
        } else {
            content
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
        .description("显示当前歌曲、封面和歌词")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct BeansWidgetBundle: WidgetBundle {
    var body: some Widget {
        BeansWidget()
    }
}
