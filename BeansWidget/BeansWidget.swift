import Foundation
import SwiftUI
import UIKit
import WidgetKit
import AppIntents
import OSLog

private let widgetGroupID = "group.com.beans.music"
private let widgetStateKey = "beans.widget.playback.state"
private let widgetCommandKey = "beans.widget.command"
private let widgetLogger = Logger(subsystem: "com.beans.app.widget", category: "playback")

@available(iOS 17.0, *)
private enum WidgetCommandIntentSupport {
    static func send(_ command: String) {
        guard let defaults = UserDefaults(suiteName: widgetGroupID) else {
            widgetLogger.error("shared defaults unavailable command=\(command, privacy: .public)")
            return
        }
        let commandID = UUID().uuidString
        defaults.set(
            [
                "id": commandID,
                "name": command,
                "createdAt": Date().timeIntervalSince1970
            ],
            forKey: widgetCommandKey
        )
        applyOptimisticState(for: command, defaults: defaults)
        defaults.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "BeansWidget")
    }

    private static func applyOptimisticState(
        for command: String,
        defaults: UserDefaults
    ) {
        guard let data = defaults.data(forKey: widgetStateKey) else { return }
        do {
            var state = try JSONDecoder().decode(WidgetPlaybackState.self, from: data)
            if command == "playPause" {
                state.isPlaying.toggle()
            }
            state.updatedAt = Date()
            defaults.set(try JSONEncoder().encode(state), forKey: widgetStateKey)
        } catch {
            widgetLogger.error("shared state update failed command=\(command, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }
}

@available(iOS 17.0, *)
private struct WidgetPlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "播放或暂停"
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        WidgetCommandIntentSupport.send("playPause")
        return .result()
    }
}

@available(iOS 17.0, *)
private struct WidgetPreviousIntent: AppIntent {
    static var title: LocalizedStringResource = "上一首"
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        WidgetCommandIntentSupport.send("previous")
        return .result()
    }
}

@available(iOS 17.0, *)
private struct WidgetNextIntent: AppIntent {
    static var title: LocalizedStringResource = "下一首"
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        WidgetCommandIntentSupport.send("next")
        return .result()
    }
}

private struct WidgetPlaybackState: Codable {
    let songKey: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let progress: Double
    var isPlaying: Bool
    let lyricRaw: String
    let coverFileName: String?
    let colorHex: String?
    var updatedAt: Date
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
        guard let defaults = UserDefaults(suiteName: widgetGroupID) else {
            widgetLogger.error("shared defaults unavailable while reading state")
            return nil
        }
        guard let data = defaults.data(forKey: widgetStateKey) else {
            widgetLogger.debug("shared playback state is empty")
            return nil
        }
        do {
            return try JSONDecoder().decode(WidgetPlaybackState.self, from: data)
        } catch {
            widgetLogger.error("shared playback state decode failed bytes=\(data.count, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
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
            widgetLogger.error("shared container unavailable while loading cover")
            return nil
        }
        let url = container.appendingPathComponent(fileName)
        guard let image = UIImage(contentsOfFile: url.path) else {
            widgetLogger.error("shared cover unavailable filename=\(fileName, privacy: .public)")
            return nil
        }
        return image
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
        .clipShape(RoundedRectangle(cornerRadius: family == .systemSmall ? 22 : 26, style: .continuous))
        .modifier(
            WidgetContainerBackground(
                cover: entry.cover,
                accent: entry.accent,
                colorScheme: colorScheme
            )
        )
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

    var recordCover: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.78))
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
            if let image = entry.cover {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .padding(9)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
            }
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.white.opacity(0.1), .black.opacity(0.85), .white.opacity(0.1)],
                        center: .center
                    ),
                    lineWidth: 5
                )
                .padding(4)
        }
        .shadow(color: .black.opacity(0.38), radius: 10, y: 6)
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

    @ViewBuilder
    var playButton: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: WidgetPlayPauseIntent()) {
                playLabel
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: URL(string: "beansmusic://widget/playPause")!) {
                playLabel
            }
        }
    }

    var playLabel: some View {
        Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(entry.accent, in: Circle())
    }

    @ViewBuilder
    var previousButton: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: WidgetPreviousIntent()) {
                previousLabel
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: URL(string: "beansmusic://widget/previous")!) {
                previousLabel
            }
        }
    }

    var previousLabel: some View {
        Image(systemName: "backward.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(primary.opacity(0.76))
            .frame(width: 30, height: 30)
    }

    @ViewBuilder
    var nextButton: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            Button(intent: WidgetNextIntent()) {
                nextLabel
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: URL(string: "beansmusic://widget/next")!) {
                nextLabel
            }
        }
    }

    var nextLabel: some View {
        Image(systemName: "forward.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(primary.opacity(0.76))
            .frame(width: 30, height: 30)
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
                    playButton
                }
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    var mediumLayout: some View {
        ZStack {
            widgetBackdrop
            HStack(spacing: 13) {
                Link(destination: URL(string: "beansmusic://widget/open")!) {
                    recordCover
                        .frame(width: 92, height: 92)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(entry.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(entry.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    progressLine
                    HStack {
                        Text(formatTime(entry.progress))
                        Spacer()
                        Text(formatTime(entry.duration))
                    }
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
                    HStack(spacing: 2) {
                        previousButton
                        Spacer()
                        playButton
                        Spacer()
                        nextButton
                    }
                    .frame(height: 36)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
        }
    }

    var largeLayout: some View {
        ZStack {
            widgetBackdrop
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: entry.isPlaying ? "waveform" : "music.note")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.78))
                    Text("BEANS MUSIC")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(.white.opacity(0.58))
                    Spacer()
                    Text(entry.isPlaying ? "正在播放" : "已暂停")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }

                HStack(spacing: 16) {
                    Link(destination: URL(string: "beansmusic://widget/open")!) {
                        recordCover
                            .frame(width: 126, height: 126)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(entry.artist)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                        Text(entry.album.isEmpty ? "正在播放" : entry.album)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }

                progressLine
                HStack {
                    Text(formatTime(entry.progress))
                    Spacer()
                    Text(formatTime(entry.duration))
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))

                HStack {
                    previousButton
                    Spacer()
                    playButton
                    Spacer()
                    nextButton
                }
                .frame(height: 38)
            }
            .padding(17)
        }
    }

    var widgetBackdrop: some View {
        ZStack {
            if let image = entry.cover {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 30)
                    .scaleEffect(1.2)
                    .overlay(.black.opacity(0.48))
            } else {
                LinearGradient(
                    colors: [entry.accent.opacity(0.72), .black.opacity(0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            LinearGradient(
                colors: [.black.opacity(0.08), .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    func formatTime(_ value: Double) -> String {
        let total = max(0, Int(value))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct WidgetContainerBackground: ViewModifier {
    let cover: UIImage?
    let accent: Color
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        let background = ZStack {
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 28)
                    .scaleEffect(1.18)
                    .overlay(Color.black.opacity(colorScheme == .dark ? 0.45 : 0.3))
            } else {
                LinearGradient(
                    colors: [accent, accent.opacity(0.38), .black.opacity(0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            LinearGradient(
                colors: [
                    .black.opacity(colorScheme == .dark ? 0.22 : 0.08),
                    .black.opacity(colorScheme == .dark ? 0.72 : 0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
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
