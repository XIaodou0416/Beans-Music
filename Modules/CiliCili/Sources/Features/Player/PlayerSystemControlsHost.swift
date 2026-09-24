import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class PlayerSystemControlsController: ObservableObject {
    private weak var volumeView: MPVolumeView?
    private weak var screen: UIScreen?
    private var outputVolumeCancellable: AnyCancellable?

    @Published private(set) var outputVolume: Float

    init() {
        let audioSession = AVAudioSession.sharedInstance()
        outputVolume = audioSession.outputVolume
        outputVolumeCancellable = audioSession.publisher(for: \.outputVolume, options: [.new])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.outputVolume = value
            }
    }

    var displayBrightness: Float? {
        screen.map { Float($0.brightness) }
    }

    func attach(volumeView: MPVolumeView, screen: UIScreen?) {
        self.volumeView = volumeView
        self.screen = screen
    }

    func setOutputVolume(_ value: Float) {
        guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.setValue(min(max(value, 0), 1), animated: false)
        slider.sendActions(for: .valueChanged)
    }

    func setDisplayBrightness(_ value: Float) {
        screen?.brightness = CGFloat(min(max(value, 0), 1))
    }
}

struct PlayerSystemControlsHost: UIViewRepresentable {
    let controller: PlayerSystemControlsController

    func makeUIView(context _: Context) -> PlayerSystemControlsHostView {
        let view = PlayerSystemControlsHostView()
        view.onScreenChange = { [weak controller] volumeView, screen in
            controller?.attach(volumeView: volumeView, screen: screen)
        }
        controller.attach(
            volumeView: view.volumeView,
            screen: view.window?.windowScene?.screen
        )
        return view
    }

    func updateUIView(_ uiView: PlayerSystemControlsHostView, context _: Context) {
        controller.attach(
            volumeView: uiView.volumeView,
            screen: uiView.window?.windowScene?.screen
        )
    }
}

final class PlayerSystemControlsHostView: UIView {
    let volumeView = MPVolumeView(frame: .zero)
    var onScreenChange: ((MPVolumeView, UIScreen?) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        volumeView.showsVolumeSlider = true
        volumeView.isUserInteractionEnabled = false
        addSubview(volumeView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        volumeView.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onScreenChange?(volumeView, window?.windowScene?.screen)
    }
}
