import Combine
import SwiftUI
import UIKit

struct ZoomySourceFrameReader: UIViewRepresentable {
    let onFrameChange: (UIView, CGRect) -> Void

    func makeUIView(context _: Context) -> FrameView {
        let view = FrameView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onFrameChange = onFrameChange
        return view
    }

    func updateUIView(_ view: FrameView, context _: Context) {
        view.onFrameChange = onFrameChange
        view.reportFrame()
    }

    final class FrameView: UIView {
        var onFrameChange: ((UIView, CGRect) -> Void)?
        private var lastReportedFrame = CGRect.null

        override func layoutSubviews() {
            super.layoutSubviews()
            reportFrame()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportFrame()
        }

        func reportFrame() {
            guard let window, bounds.width > 1, bounds.height > 1 else { return }
            let frame = convert(bounds, to: window).integral
            guard frame != lastReportedFrame else { return }
            lastReportedFrame = frame
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastReportedFrame == frame else { return }
                self.onFrameChange?(self, frame)
            }
        }
    }
}

@MainActor
final class ZoomySourceAnchor: ObservableObject {
    weak var view: UIView?
    private var windowFrame: CGRect = .zero

    func update(view: UIView, windowFrame: CGRect) {
        self.view = view
        self.windowFrame = windowFrame
    }

    func frame(in container: UIView) -> CGRect? {
        if let view,
           let viewWindow = view.window,
           let containerWindow = container.window,
           viewWindow === containerWindow,
           view.bounds.width > 1,
           view.bounds.height > 1 {
            let convertedFrame = view.convert(view.bounds, to: container).integral
            if isUsableSourceFrame(convertedFrame, in: container) {
                return convertedFrame
            }
        }

        guard windowFrame.width > 1, windowFrame.height > 1 else { return nil }
        let convertedFrame: CGRect
        if let window = container.window {
            convertedFrame = container.convert(windowFrame, from: window).integral
        } else {
            convertedFrame = windowFrame.integral
        }
        return isUsableSourceFrame(convertedFrame, in: container) ? convertedFrame : nil
    }

    private func isUsableSourceFrame(_ frame: CGRect, in container: UIView) -> Bool {
        frame.width > 1
            && frame.height > 1
            && frame.intersects(container.bounds.insetBy(dx: -40, dy: -40))
    }
}

struct ZoomyThumbnailImageView: UIViewRepresentable {
    let image: UIImage?
    let cornerRadius: CGFloat
    let contentMode: UIView.ContentMode
    let contentAlignment: ZoomyImageContentAlignment

    func makeUIView(context _: Context) -> ZoomyThumbnailUIImageView {
        let imageView = ZoomyThumbnailUIImageView()
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        imageView.isOpaque = false
        imageView.isUserInteractionEnabled = false
        imageView.displayContentMode = contentMode
        imageView.contentAlignment = contentAlignment
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.layer.cornerCurve = .continuous
        imageView.layer.cornerRadius = cornerRadius
        return imageView
    }

    func updateUIView(_ imageView: ZoomyThumbnailUIImageView, context _: Context) {
        imageView.image = image
        imageView.displayContentMode = contentMode
        imageView.contentAlignment = contentAlignment
        imageView.layer.cornerRadius = cornerRadius
    }
}

final class ZoomyThumbnailUIImageView: UIView {
    var image: UIImage? {
        didSet {
            guard image !== oldValue else { return }
            setNeedsDisplay()
        }
    }

    var displayContentMode: UIView.ContentMode = .scaleAspectFill {
        didSet {
            guard displayContentMode != oldValue else { return }
            setNeedsDisplay()
        }
    }

    var contentAlignment: ZoomyImageContentAlignment = .center {
        didSet {
            setNeedsDisplay()
        }
    }

    override var intrinsicContentSize: CGSize {
        .zero
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        UIGraphicsGetCurrentContext()?.interpolationQuality = .high
        image.draw(in: imageRect(for: image.size, in: bounds))
    }

    private func imageRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let scale: CGFloat

        switch displayContentMode {
        case .scaleAspectFit:
            scale = min(widthScale, heightScale)
        case .scaleAspectFill:
            scale = max(widthScale, heightScale)
        default:
            return bounds
        }

        let scaledSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let originX = bounds.midX - scaledSize.width / 2
        let originY: CGFloat
        switch contentAlignment {
        case .center:
            originY = bounds.midY - scaledSize.height / 2
        case .top:
            originY = bounds.minY
        }
        return CGRect(origin: CGPoint(x: originX, y: originY), size: scaledSize)
    }
}
