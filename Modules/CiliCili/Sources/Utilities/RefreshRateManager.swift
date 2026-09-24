import QuartzCore
import UIKit

@MainActor
final class RefreshRateManager: NSObject {
    static let shared = RefreshRateManager()
    static let isEnabledKey = "cc.bili.display.force120HzScrollingEnabled.v1"

    private var displayLink: CADisplayLink?

    private override init() {
        super.init()
    }

    func restorePersistedPreference() {
        setForce120HzEnabled(
            UserDefaults.standard.bool(forKey: Self.isEnabledKey),
            persists: false
        )
    }

    func setForce120HzEnabled(_ isEnabled: Bool, persists: Bool = true) {
        if persists {
            UserDefaults.standard.set(isEnabled, forKey: Self.isEnabledKey)
        }

        if isEnabled {
            enableForce120Hz()
        } else {
            disableForce120Hz()
        }
    }

    func enableForce120Hz() {
        guard displayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 120,
            maximum: 120,
            preferred: 120
        )
        link.add(to: .main, forMode: .common)
        link.isPaused = false
        displayLink = link
    }

    func disableForce120Hz() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkDidFire(_: CADisplayLink) {}
}
