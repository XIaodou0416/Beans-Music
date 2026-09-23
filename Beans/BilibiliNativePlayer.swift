import SwiftUI
import AVKit

@MainActor
final class BilibiliNativePlayer: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var loading = true
    @Published private(set) var error: String?
    private var alternatives: [URL] = []
    private var itemObserver: NSKeyValueObservation?
    private var timeObserver: NSKeyValueObservation?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var request: Task<Void, Never>?

    func open(resumeAt: Double = 0, _ loader: @escaping () async throws -> [URL]) {
        stop()
        let token = UUID()
        generation = token
        loading = true
        error = nil
        request = Task {
            do {
                let urls = try await loader()
                try Task.checkCancellation()
                guard token == generation else { return }
                guard !urls.isEmpty else { throw BilibiliError(message: "暂无可播放视频地址") }
                alternatives = urls
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
                nextURL(resume: resumeAt)
            } catch is CancellationError { }
            catch {
                guard generation == token else { return }
                loading = false
                self.error = error.localizedDescription
            }
        }
    }
    private func nextURL(resume: Double) {
        itemObserver = nil
        timeObserver = nil
        timeout?.cancel()
        player?.pause()
        guard !alternatives.isEmpty else {
            loading = false
            error = "视频加载失败，所有备用地址均不可用，请重试"
            return
        }
        let url = alternatives.removeFirst()
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": BilibiliAPI.headers])
        let item = AVPlayerItem(asset: asset)
        let nextPlayer = AVPlayer(playerItem: item)
        player = nextPlayer
        loading = true
        let token = generation
        itemObserver = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, let item, token == self.generation, self.player?.currentItem === item else { return }
                if item.status == .failed { self.nextURL(resume: resume) }
            }
        }
        timeObserver = nextPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self, weak nextPlayer] _, _ in
            Task { @MainActor in
                guard let self, let nextPlayer, token == self.generation, self.player === nextPlayer else { return }
                if nextPlayer.timeControlStatus == .playing {
                    self.loading = false
                    self.timeout?.cancel()
                }
            }
        }
        if resume > 0 { nextPlayer.seek(to: CMTime(seconds: resume, preferredTimescale: 600)) }
        nextPlayer.play()
        timeout = Task { [weak self, weak nextPlayer] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            guard let self, let nextPlayer, token == self.generation, self.player === nextPlayer, self.loading else { return }
            self.nextURL(resume: resume)
        }
    }
    func pause() { player?.pause(); timeout?.cancel() }
    func stop() {
        generation = UUID()
        request?.cancel()
        timeout?.cancel()
        itemObserver = nil
        timeObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        alternatives = []
    }
}

struct BilibiliVideoSurface: View {
    @ObservedObject var model: BilibiliNativePlayer
    let retry: () -> Void
    var body: some View {
        ZStack {
            Color.black
            if let player = model.player { BilibiliPlayerController(player: player) }
            if model.loading { ProgressView().tint(.white).allowsHitTesting(false) }
            if let error = model.error {
                VStack(spacing: 10) {
                    Text(error).font(.footnote).multilineTextAlignment(.center)
                    Button("重新播放", action: retry).buttonStyle(.bordered)
                }.foregroundStyle(.white).padding()
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}
private struct BilibiliPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.showsPlaybackControls = true
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) { controller.player = nil }
}
