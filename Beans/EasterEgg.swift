import SwiftUI
import AVFoundation
import WebKit

@MainActor
private final class EasterEggAudioPlayer {
    static let shared = EasterEggAudioPlayer()

    private var player: AVAudioPlayer?

    @discardableResult
    func play() -> TimeInterval {
        guard let url = Bundle.main.url(forResource: "EasterEggSound", withExtension: "m4a") else { return 0 }
        do {
            player?.stop()
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            return newPlayer.duration
        } catch {
            player = nil
            return 0
        }
    }
}

private struct FallingFoot: Identifiable {
    let id = UUID()
    let horizontalPosition: CGFloat
    let scale: CGFloat
    let rotation: Double
    let delay: TimeInterval
    let duration: TimeInterval
}

struct EasterEggOverlay: View {
    let onDismiss: () -> Void

    @State private var animatedFootScale: CGFloat = 0.84
    @State private var fallingFoots: [FallingFoot] = []
    @State private var fallingFootsStarted = false
    @State private var didStart = false

    private static let fallingFoot = Bundle.main.url(forResource: "EasterEggFallingFoot", withExtension: "png")
        .flatMap { UIImage(contentsOfFile: $0.path) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.78)
                    .ignoresSafeArea()

                AnimatedWebPView(resourceName: "EasterEggFoot")
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(animatedFootScale)
                    .shadow(color: .black.opacity(0.34), radius: 26, y: 12)

                if let fallingFoot = Self.fallingFoot {
                    ForEach(fallingFoots) { foot in
                        Image(uiImage: fallingFoot)
                            .resizable()
                            .scaledToFit()
                            .frame(width: min(108, max(64, proxy.size.width * 0.22)) * foot.scale)
                            .rotationEffect(.degrees(foot.rotation))
                            .position(
                                x: proxy.size.width * foot.horizontalPosition,
                                y: fallingFootsStarted ? proxy.size.height + 120 : -120
                            )
                            .animation(.linear(duration: foot.duration).delay(foot.delay), value: fallingFootsStarted)
                            .allowsHitTesting(false)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
            .onAppear {
                guard !didStart else { return }
                didStart = true
                let audioDuration = EasterEggAudioPlayer.shared.play()
                let displayDuration = max(audioDuration, 0.8)
                fallingFoots = makeFallingFoots(for: displayDuration)
                withAnimation(.spring(response: 0.46, dampingFraction: 0.62)) {
                    animatedFootScale = 1
                }
                DispatchQueue.main.async {
                    fallingFootsStarted = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration) {
                    onDismiss()
                }
            }
        }
        .ignoresSafeArea()
    }

    private func makeFallingFoots(for audioDuration: TimeInterval) -> [FallingFoot] {
        let patterns: [(CGFloat, CGFloat, Double)] = [
            (0.12, 0.72, -18), (0.33, 0.82, 13), (0.54, 0.68, -9),
            (0.76, 0.78, 19), (0.90, 0.64, -15), (0.23, 0.74, 10),
            (0.46, 0.86, -21), (0.68, 0.70, 16), (0.84, 0.80, -7)
        ]
        let travelDuration = max(1.65, min(3.1, audioDuration * 0.48))
        let count = min(patterns.count, max(5, Int((audioDuration / 0.72).rounded(.up))))
        let finalDelay = max(0, audioDuration - travelDuration - 0.08)
        return patterns.prefix(count).enumerated().map { index, pattern in
            FallingFoot(
                horizontalPosition: pattern.0,
                scale: pattern.1,
                rotation: pattern.2,
                delay: count > 1 ? finalDelay * Double(index) / Double(count - 1) : 0,
                duration: travelDuration
            )
        }
    }
}

private struct AnimatedWebPView: UIViewRepresentable {
    let resourceName: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = false
        webView.contentMode = .scaleAspectFit

        if let url = Bundle.main.url(forResource: resourceName, withExtension: "webp") {
            let html = """
            <!doctype html><html><head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no\"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}img{width:100%;height:100%;object-fit:cover}</style></head><body><img src=\"\(url.lastPathComponent)\" /></body></html>
            """
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
