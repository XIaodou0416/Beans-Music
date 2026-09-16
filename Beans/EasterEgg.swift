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

    @State private var animatedFootScale: CGFloat = 0.24
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
                    .frame(
                        width: min(proxy.size.width * 0.92, 620),
                        height: min(proxy.size.height * 0.72, 620)
                    )
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
            (0.08, 0.62, -18), (0.17, 0.72, 11), (0.27, 0.66, -9),
            (0.37, 0.78, 17), (0.47, 0.60, -14), (0.57, 0.70, 8),
            (0.67, 0.64, -20), (0.77, 0.76, 15), (0.88, 0.61, -7),
            (0.13, 0.69, 20), (0.23, 0.58, -12), (0.34, 0.74, 9),
            (0.52, 0.63, -17), (0.63, 0.73, 14), (0.74, 0.59, -8),
            (0.94, 0.68, 18), (0.06, 0.57, -6), (0.30, 0.67, 16),
            (0.41, 0.55, -15), (0.58, 0.65, 7), (0.70, 0.75, -19),
            (0.82, 0.56, 12), (0.97, 0.64, -10), (0.49, 0.71, 21)
        ]
        let travelDuration = max(1.65, min(3.1, audioDuration * 0.48))
        let count = min(patterns.count, max(22, Int((audioDuration / 0.30).rounded(.up))))
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
            <!doctype html><html><head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no\"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}img{width:100%;height:100%;object-fit:contain}</style></head><body><img src=\"\(url.lastPathComponent)\" /></body></html>
            """
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
