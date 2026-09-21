import SwiftUI

/// Renders a lyric line with a real word timeline when one is available.
/// The timeline is intentionally isolated from the lyric list so only the active
/// line gets per-frame work.
struct KaraokeLyricText: View {
    let line: LyricLine
    let currentTime: Double
    let isPlaying: Bool
    let isActive: Bool
    let enabled: Bool
    let font: Font
    let style: AnyShapeStyle
    let fallbackOpacity: Double

    @State private var anchorDate = Date()
    @State private var anchorTime = 0.0

    var body: some View {
        if enabled, isActive, let words = line.words, !words.isEmpty {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
                let elapsed = isPlaying
                    ? anchorTime + max(0, context.date.timeIntervalSince(anchorDate))
                    : currentTime
                wordView(words: words, time: elapsed)
            }
            .onAppear {
                anchorDate = Date()
                anchorTime = currentTime
            }
            .onChange(of: currentTime) { value in
                anchorDate = Date()
                anchorTime = value
            }
        } else {
            Text(line.text.isEmpty ? " " : line.text)
                .font(font)
                .foregroundStyle(style)
                .opacity(isActive ? 1 : fallbackOpacity)
        }
    }

    private func wordView(words: [LyricWord], time: Double) -> some View {
        // Compose one Text value instead of placing every English word in an
        // HStack. Separate Text views can be independently compressed and
        // wrapped, which makes Latin lyrics appear out of order or scattered.
        var composed = Text("")
        for word in words {
            composed = composed + Text(verbatim: word.text)
                .foregroundStyle(style)
                .opacity(LyricKaraokeTiming.opacity(for: word, at: time))
        }
        return composed
            .font(font)
            .multilineTextAlignment(.leading)
    }
}
