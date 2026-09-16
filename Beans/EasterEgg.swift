import SwiftUI
import AVFoundation
import WebKit

@MainActor
private final class EasterEggAudioPlayer {
    static let shared = EasterEggAudioPlayer()

    private var player: AVAudioPlayer?

    func play() {
        guard let url = Bundle.main.url(forResource: "EasterEggSound", withExtension: "m4a") else { return }
        do {
            player?.stop()
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
        } catch {
            player = nil
        }
    }
}

struct EasterEggOverlay: View {
    let onDismiss: () -> Void

    @State private var animatedFootScale: CGFloat = 0.24
    @State private var fallingFootOffset: CGFloat = -900
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
                    Image(uiImage: fallingFoot)
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(proxy.size.width * 0.72, 420))
                        .rotationEffect(.degrees(-12))
                        .offset(x: proxy.size.width * 0.20, y: fallingFootOffset)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
            .onAppear {
                guard !didStart else { return }
                didStart = true
                EasterEggAudioPlayer.shared.play()
                withAnimation(.spring(response: 0.46, dampingFraction: 0.62)) {
                    animatedFootScale = 1
                }
                withAnimation(.linear(duration: 3.1).delay(0.08)) {
                    fallingFootOffset = proxy.size.height + 500
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) {
                    onDismiss()
                }
            }
        }
        .ignoresSafeArea()
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
