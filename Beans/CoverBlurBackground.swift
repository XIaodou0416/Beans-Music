import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// MARK: - 封面毛玻璃背景（UIKit 独立图层，不参与 SwiftUI 布局）
//
// 为什么这样做不会错乱：
// - 背景封面的加载/模糊/换图全部在 UIKit 层（CoverBlurView）内完成，
//   不经过 SwiftUI 的 @State / body 重算，因此封面加载完成不会触发
//   任何 SwiftUI 布局更新 —— 从根上消除"封面加载后布局错乱"。
// - 该视图在 SwiftUI 中只占一个固定全屏 frame（maxWidth/maxHeight: infinity），
//   图片是否加载、加载哪张图都不改变它的尺寸。
// - 切歌换图使用 UIView 交叉溶解过渡，视觉平滑。
//
// 发热优化：不使用 UIVisualEffectView 实时模糊（整屏 GPU 实时模糊是发热大头），
// 而是切歌时在后台队列一次性生成高斯模糊封面图并缓存，前台只做静态显示，
// 效果更明显且几乎零持续开销。

struct CoverBlurBackground: UIViewRepresentable {
    let url: URL?
    let scheme: ColorScheme
    var animationsEnabled = true

    func makeUIView(context: Context) -> CoverBlurView {
        let view = CoverBlurView()
        view.updateScheme(scheme)
        view.setAnimationsEnabled(animationsEnabled)
        view.load(url: url)
        return view
    }

    func updateUIView(_ uiView: CoverBlurView, context: Context) {
        uiView.updateScheme(scheme)
        uiView.setAnimationsEnabled(animationsEnabled)
        uiView.load(url: url)
    }
}

final class CoverBlurView: UIView {
    private let imageView = UIImageView()
    private let gradientLayer = CAGradientLayer()
    private let gradientHost = UIView()
    private let tintView = UIView()
    private var currentURL: URL?
    private var animationsEnabled = true
    private static let imageCache = NSCache<NSURL, UIImage>()
    private static let blurQueue = DispatchQueue(label: "beans.coverblur", qos: .utility)
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        tintView.isUserInteractionEnabled = false
        gradientHost.isUserInteractionEnabled = false

        gradientLayer.colors = [UIColor.systemGray.cgColor, UIColor.systemGray2.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.opacity = 0.62
        gradientHost.layer.addSublayer(gradientLayer)

        addSubview(imageView)
        addSubview(gradientHost)
        addSubview(tintView)
        startBackgroundAnimations()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientHost.frame = bounds
        gradientLayer.frame = bounds
        imageView.frame = bounds
        tintView.frame = bounds
    }

    /// 背景动态效果：模糊封面缓慢呼吸缩放（UIView 循环动画，可靠运行）+ 主色渐变端点缓慢摆动。
    /// 长周期低频 + GPU 合成，不触发 SwiftUI 布局，也几乎不增加耗电。
    private func startBackgroundAnimations() {
        guard animationsEnabled else { return }
        // 重新触发时先取消旧动画，避免堆叠
        imageView.layer.removeAnimation(forKey: "beansBgBreathe")
        gradientLayer.removeAnimation(forKey: "beansGradStart")
        gradientLayer.removeAnimation(forKey: "beansGradEnd")
        imageView.transform = .identity

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.10
        scale.duration = 14
        scale.autoreverses = true
        scale.repeatCount = .infinity
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageView.layer.add(scale, forKey: "beansBgBreathe")

        let start = CABasicAnimation(keyPath: "startPoint")
        start.fromValue = NSValue(cgPoint: CGPoint(x: 0.5, y: 0))
        start.toValue = NSValue(cgPoint: CGPoint(x: 0.68, y: 0))
        start.duration = 12
        start.autoreverses = true
        start.repeatCount = .infinity
        start.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(start, forKey: "beansGradStart")

        let end = CABasicAnimation(keyPath: "endPoint")
        end.fromValue = NSValue(cgPoint: CGPoint(x: 0.5, y: 1))
        end.toValue = NSValue(cgPoint: CGPoint(x: 0.32, y: 1))
        end.duration = 12
        end.autoreverses = true
        end.repeatCount = .infinity
        end.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(end, forKey: "beansGradEnd")
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        guard animationsEnabled != enabled else { return }
        animationsEnabled = enabled
        if enabled {
            startBackgroundAnimations()
        } else {
            imageView.layer.removeAnimation(forKey: "beansBgBreathe")
            gradientLayer.removeAnimation(forKey: "beansGradStart")
            gradientLayer.removeAnimation(forKey: "beansGradEnd")
        }
    }

    func updateScheme(_ scheme: ColorScheme) {
        // 深浅遮罩：压暗/提亮背景，保证前景文字与控件始终可读
        tintView.backgroundColor = scheme == .dark
            ? UIColor.black.withAlphaComponent(0.30)
            : UIColor.white.withAlphaComponent(0.10)
    }

    func load(url: URL?) {
        guard let url else {
            imageView.image = nil
            return
        }
        // 相同封面不重复加载/重设，避免播放器高频重绘时反复赋值
        if currentURL == url { return }
        currentURL = url

        if url.isFileURL, let source = CustomCoverMedia.previewImage(at: url) {
            Self.blurQueue.async { [weak self] in
                let blurred = Self.makeBlurredImage(source)
                let colors = Self.extractGradientColors(from: source)
                if let blurred {
                    Self.imageCache.setObject(blurred, forKey: url as NSURL)
                }
                DispatchQueue.main.async {
                    guard let self, self.currentURL == url else { return }
                    if let blurred { self.setImage(blurred, animated: true) }
                    self.applyGradient(colors)
                }
            }
            return
        }

        if let cached = Self.imageCache.object(forKey: url as NSURL) {
            setImage(cached, animated: false)
            applyGradientIfNeeded(for: url)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let source = UIImage(data: data) else { return }
            Self.blurQueue.async {
                let blurred = Self.makeBlurredImage(source)
                let colors = Self.extractGradientColors(from: source)
                if let blurred {
                    Self.imageCache.setObject(blurred, forKey: url as NSURL)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.currentURL == url else { return }
                    if let blurred { self.setImage(blurred, animated: true) }
                    self.applyGradient(colors)
                }
            }
        }.resume()
    }

    /// 应用封面主色渐变（带过渡动画）
    private func applyGradient(_ colors: (top: UIColor, bottom: UIColor)) {
        guard animationsEnabled else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradientLayer.colors = [colors.top.cgColor, colors.bottom.cgColor]
            CATransaction.commit()
            return
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.6)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        gradientLayer.colors = [colors.top.cgColor, colors.bottom.cgColor]
        CATransaction.commit()
    }

    private func applyGradientIfNeeded(for url: URL) {
        // 缓存命中时从缓存图重算一次（成本低，仅切歌时触发一次）
        if let cached = Self.imageCache.object(forKey: url as NSURL) {
            let colors = Self.extractGradientColors(from: cached)
            CATransaction.begin()
            CATransaction.setDisableActions(!animationsEnabled)
            CATransaction.setAnimationDuration(animationsEnabled ? 0.6 : 0)
            gradientLayer.colors = [colors.top.cgColor, colors.bottom.cgColor]
            CATransaction.commit()
        }
    }

    /// 封面主色渐变：从封面提取上下区域平均色，生成与封面协调的动态渐变背景
    private static func extractGradientColors(from image: UIImage) -> (top: UIColor, bottom: UIColor) {
        let sample = image.preparingThumbnail(of: CGSize(width: 200, height: 200)) ?? image
        // CIImage 坐标原点在左下：视觉上方 = y 比例 0.5...1.0，视觉下方 = 0...0.5
        let top = areaAverage(of: sample, in: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
            ?? UIColor.systemGray
        let bottom = areaAverage(of: sample, in: CGRect(x: 0, y: 0, width: 1, height: 0.5))
            ?? UIColor.systemGray2
        return (top.lightened(0.28), bottom.darkened(0.48))
    }

    private static func areaAverage(of image: UIImage, in normalizedRect: CGRect) -> UIColor? {
        guard let ci = CIImage(image: image) else { return nil }
        let extent = ci.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let region = CGRect(
            x: extent.minX + extent.width * normalizedRect.minX,
            y: extent.minY + extent.height * normalizedRect.minY,
            width: extent.width * normalizedRect.width,
            height: extent.height * normalizedRect.height
        )
        let filter = CIFilter.areaAverage()
        filter.inputImage = ci
        filter.extent = region
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }

    /// 一次性高斯模糊：先缩小再模糊，最后放回全屏展示，观感更明显、开销更低
    private static func makeBlurredImage(_ source: UIImage) -> UIImage? {
        let target = source.preparingThumbnail(of: CGSize(width: 480, height: 480)) ?? source
        guard let input = CIImage(image: target) else { return target }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input
        filter.radius = 36
        guard let output = filter.outputImage else { return target }
        let extent = output.extent
        guard extent.width > 0, extent.height > 0,
              let cg = ciContext.createCGImage(output, from: extent) else { return target }
        return UIImage(cgImage: cg)
    }

    private func setImage(_ image: UIImage, animated: Bool) {
        guard animated, animationsEnabled, imageView.image != nil else {
            imageView.image = image
            startBackgroundAnimations()
            return
        }
        UIView.transition(
            with: imageView,
            duration: 0.4,
            options: [.transitionCrossDissolve, .beginFromCurrentState]
        ) {
            self.imageView.image = image
        } completion: { _ in
            // 切歌过渡结束后重新确保背景动画持续运行
            self.startBackgroundAnimations()
        }
    }
}


private extension UIColor {
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let a = min(max(amount, 0), 1)
        return UIColor(
            red: r1 * (1 - a) + r2 * a,
            green: g1 * (1 - a) + g2 * a,
            blue: b1 * (1 - a) + b2 * a,
            alpha: 1
        )
    }

    func lightened(_ amount: CGFloat) -> UIColor { mixed(with: .white, amount: amount) }
    func darkened(_ amount: CGFloat) -> UIColor { mixed(with: .black, amount: amount) }
}
