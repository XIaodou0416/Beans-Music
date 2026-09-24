import SwiftUI
import AVKit
import Combine
import UIKit

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

struct BilibiliDetailVideoSurface: View {
    @ObservedObject var model: BilibiliNativePlayer
    @Binding var quality: Int
    let onBack: () -> Void
    let onExpand: () -> Void
    @State private var controlsVisible = true
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var seekTime = 0.0
    @State private var isSeeking = false

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black
            if let player = model.player {
                BilibiliPlayerLayerView(player: player)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) { controlsVisible.toggle() }
                }
            if model.loading {
                ProgressView().tint(.white).allowsHitTesting(false)
            }
            if let error = model.error {
                VStack(spacing: 10) {
                    Text(error).font(.footnote).multilineTextAlignment(.center)
                    Button("重新播放") { model.player?.play() }
                        .buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
                .padding()
            }
            if controlsVisible { controls.transition(.opacity) }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(Color.black)
        .clipped()
        .onReceive(timer) { _ in updatePlaybackTime() }
        .onChange(of: model.player?.currentItem?.duration.seconds) { _ in updatePlaybackTime() }
    }

    private var controls: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.black.opacity(0.48), .clear, .clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack {
                HStack {
                    playerButton("chevron.left", label: "返回", action: onBack)
                    Spacer()
                }
                Spacer(minLength: 4)
                VStack(spacing: 7) {
                    Slider(value: sliderValue, in: 0...max(duration, 1), onEditingChanged: seekEditingChanged)
                        .tint(Color(red: 0.98, green: 0.31, blue: 0.53))
                    HStack(spacing: 10) {
                        Button {
                            if model.player?.timeControlStatus == .playing { model.pause() }
                            else { model.player?.play() }
                        } label: {
                            Image(systemName: model.player?.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.player?.timeControlStatus == .playing ? "暂停" : "播放")

                        Text("\(timeLabel(isSeeking ? seekTime : currentTime)) / \(timeLabel(duration))")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize()
                        Spacer(minLength: 4)
                        Menu {
                            Button("流畅") { quality = 16 }
                            Button("高清") { quality = 64 }
                            Button("超清") { quality = 80 }
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 34, height: 34)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("清晰度，当前\(qualityTitle)")
                        playerButton("arrow.up.left.and.arrow.down.right", label: "全屏", action: onExpand)
                    }
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 7)
        }
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { isSeeking ? seekTime : min(currentTime, max(duration, 1)) },
            set: { seekTime = $0 }
        )
    }

    private var qualityTitle: String {
        switch quality {
        case 16: return "流畅"
        case 80: return "超清"
        default: return "高清"
        }
    }

    private func playerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func seekEditingChanged(_ editing: Bool) {
        isSeeking = editing
        if !editing, let player = model.player {
            player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = seekTime
        }
    }

    private func updatePlaybackTime() {
        guard let item = model.player?.currentItem else { return }
        let itemDuration = item.duration.seconds
        if itemDuration.isFinite && itemDuration > 0 { duration = itemDuration }
        let elapsed = model.player?.currentTime().seconds ?? 0
        if elapsed.isFinite && !isSeeking {
            currentTime = max(0, elapsed)
            seekTime = currentTime
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct BilibiliPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerHostView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    static func dismantleUIView(_ view: PlayerLayerHostView, coordinator: ()) {
        view.playerLayer.player = nil
    }

    final class PlayerLayerHostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspect
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            playerLayer.videoGravity = .resizeAspect
        }
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

