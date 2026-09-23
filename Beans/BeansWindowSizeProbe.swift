import SwiftUI
import UIKit

/// The keyboard reduces a GeometryReader's proposed height; it does not rotate
/// the app window. Use the actual window size to choose the iPad shell.
struct BeansWindowSizeProbe: UIViewRepresentable {
    let onSize: (CGSize) -> Void
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.onSize = onSize
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: Probe, context: Context) { view.onSize = onSize; view.report() }
    final class Probe: UIView {
        var onSize: ((CGSize) -> Void)?
        private var lastSize = CGSize.zero
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        func report() {
            guard let window, window.bounds.width > 0, window.bounds.height > 0 else { return }
            let size = window.bounds.size
            guard size != lastSize else { return }
            lastSize = size
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.lastSize == size else { return }
                self.onSize?(size)
            }
        }
    }
}
