import SwiftUI
import UIKit

struct DynamicAttributedTextLabel: UIViewRepresentable {
    let input: DynamicAttributedTextInput
    let preferredWidth: CGFloat?
    let onURLTap: (URL) -> Void
    let onNonLinkTap: (() -> Void)?
    let onContentLayoutChange: (() -> Void)?
    private static let sharedRenderCache = DynamicAttributedTextRenderCache()

    init(
        input: DynamicAttributedTextInput,
        preferredWidth: CGFloat?,
        onURLTap: @escaping (URL) -> Void,
        onNonLinkTap: (() -> Void)?,
        onContentLayoutChange: (() -> Void)? = nil
    ) {
        self.input = input
        self.preferredWidth = preferredWidth
        self.onURLTap = onURLTap
        self.onNonLinkTap = onNonLinkTap
        self.onContentLayoutChange = onContentLayoutChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> DynamicTextKitAttributedLabel {
        let label = DynamicTextKitAttributedLabel()
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: DynamicTextKitAttributedLabel, context: Context) {
        label.onLinkTap = onURLTap
        label.onNonLinkTap = onNonLinkTap
        label.onContentLayoutChange = onContentLayoutChange
        label.numberOfLines = input.maxLines ?? 0
        label.lineBreakMode = input.lineBreakMode
        let renderResult = context.coordinator.render(input)
        if context.coordinator.appliedRenderKey != renderResult.key {
            label.attributedText = renderResult.attributedString
            label.invalidateIntrinsicContentSize()
            context.coordinator.appliedRenderKey = renderResult.key
        }
        context.coordinator.currentInput = input
        context.coordinator.loadMissingImages(renderResult.missingImageURLs, into: label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DynamicTextKitAttributedLabel, context: Context) -> CGSize? {
        guard let width = context.coordinator.measuredWidth(
            proposedWidth: proposal.width,
            preferredWidth: preferredWidth,
            boundsWidth: uiView.bounds.width
        ) else {
            context.coordinator.lastMeasuredWidth = nil
            return nil
        }

        context.coordinator.lastMeasuredWidth = width
        return uiView.measuredSize(fittingWidth: width)
    }

    final class Coordinator {
        var currentInput: DynamicAttributedTextInput?
        var appliedRenderKey: String?
        var lastMeasuredWidth: CGFloat?
        private var cachedInputKey: String?
        private var cachedRenderResult: DynamicAttributedTextRenderResult?
        private var imageTasks: [URL: Task<Void, Never>] = [:]

        func measuredWidth(proposedWidth: CGFloat?, preferredWidth: CGFloat?, boundsWidth: CGFloat) -> CGFloat? {
            let preferred = validWidth(preferredWidth)
            let proposed = validWidth(proposedWidth)

            if let preferred {
                return ceil(max(preferred, proposed ?? 0))
            }

            if let proposed {
                return ceil(proposed)
            }

            if boundsWidth.isFinite, boundsWidth > 1 {
                return ceil(boundsWidth)
            }

            if let lastMeasuredWidth, lastMeasuredWidth.isFinite, lastMeasuredWidth > 1 {
                return ceil(lastMeasuredWidth)
            }

            return nil
        }

        private func validWidth(_ width: CGFloat?) -> CGFloat? {
            guard let width, width.isFinite, width > 1 else { return nil }
            return width
        }

        func render(_ input: DynamicAttributedTextInput) -> DynamicAttributedTextRenderResult {
            if cachedInputKey == input.cacheKey, let cachedRenderResult {
                return cachedRenderResult
            }

            if let result = DynamicAttributedTextLabel.sharedRenderCache.result(for: input.cacheKey) {
                cachedInputKey = input.cacheKey
                cachedRenderResult = result
                return result
            }

            let result = input.render()
            let renderResult = DynamicAttributedTextRenderResult(
                key: input.cacheKey + "|" + result.missingImageURLs.map(\.absoluteString).sorted().joined(separator: ","),
                attributedString: result.attributedString,
                missingImageURLs: result.missingImageURLs
            )
            if result.missingImageURLs.isEmpty {
                DynamicAttributedTextLabel.sharedRenderCache.set(renderResult, for: input.cacheKey)
            }
            cachedInputKey = input.cacheKey
            cachedRenderResult = renderResult
            return renderResult
        }

        func loadMissingImages(_ urls: [URL], into label: DynamicTextKitAttributedLabel) {
            guard !urls.isEmpty else { return }

            for url in urls where imageTasks[url] == nil {
                imageTasks[url] = Task { [weak self, weak label] in
                    _ = await BiliEmoteImageStore.shared.image(for: url)

                    await MainActor.run {
                        guard let self else { return }
                        self.imageTasks[url] = nil
                        guard let label, let currentInput = self.currentInput else { return }
                        self.cachedInputKey = nil
                        let renderResult = self.render(currentInput)
                        if renderResult.missingImageURLs.isEmpty {
                            DynamicAttributedTextLabel.sharedRenderCache.set(renderResult, for: currentInput.cacheKey)
                        }
                        self.appliedRenderKey = renderResult.key
                        label.attributedText = renderResult.attributedString
                        label.invalidateIntrinsicContentSize()
                        label.onContentLayoutChange?()
                    }
                }
            }
        }

        deinit {
            imageTasks.values.forEach { $0.cancel() }
        }
    }
}

final class DynamicTextKitAttributedLabel: UIView {
    var attributedText: NSAttributedString? {
        didSet {
            textStorage.setAttributedString(attributedText ?? NSAttributedString())
            accessibilityLabel = attributedText?.string
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    var numberOfLines = 0 {
        didSet {
            guard oldValue != numberOfLines else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    var lineBreakMode: NSLineBreakMode = .byWordWrapping {
        didSet {
            guard oldValue != lineBreakMode else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    var onLinkTap: ((URL) -> Void)?
    var onNonLinkTap: (() -> Void)?
    var onContentLayoutChange: (() -> Void)?

    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureTextSystem()
        installTapRecognizer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTextSystem()
        installTapRecognizer()
    }

    override var intrinsicContentSize: CGSize {
        guard bounds.width > 1 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        return measuredSize(fittingWidth: bounds.width)
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard textStorage.length > 0, bounds.width > 1 else { return }

        configureTextContainer(size: CGSize(width: bounds.width, height: bounds.height))
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
    }

    func measuredSize(fittingWidth width: CGFloat) -> CGSize {
        guard width.isFinite, width > 1, textStorage.length > 0 else {
            return CGSize(width: max(ceil(width), 0), height: 0)
        }

        configureTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: ceil(width), height: ceil(usedRect.height))
    }

    private func configureTextSystem() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
    }

    private func installTapRecognizer() {
        isUserInteractionEnabled = true
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(recognizer)
    }

    private func configureTextContainer(size: CGSize) {
        textContainer.size = CGSize(
            width: max(size.width, 0),
            height: max(size.height, 0)
        )
        textContainer.maximumNumberOfLines = numberOfLines
        textContainer.lineBreakMode = lineBreakMode
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }

        handleTap(at: recognizer.location(in: self))
    }

    func handleTap(at point: CGPoint) {
        guard let characterIndex = characterIndex(at: point),
              characterIndex >= 0,
              characterIndex < textStorage.length
        else {
            onNonLinkTap?()
            return
        }

        let attribute = textStorage.attribute(.biliMentionURL, at: characterIndex, effectiveRange: nil)
        let url: URL?
        if let directURL = attribute as? URL {
            url = directURL
        } else if let string = attribute as? String {
            url = URL(string: string)
        } else {
            url = nil
        }

        if let url, let onLinkTap {
            onLinkTap(url)
        } else {
            onNonLinkTap?()
        }
    }

    private func characterIndex(at point: CGPoint) -> Int? {
        guard textStorage.length > 0, bounds.width > 1 else { return nil }

        configureTextContainer(size: bounds.size)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        guard usedRect.insetBy(dx: -8, dy: -8).contains(point) else { return nil }

        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        guard glyphRect.insetBy(dx: -10, dy: -8).contains(point) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }
}

private final class DynamicAttributedTextRenderCache {
    private let cache = NSCache<NSString, DynamicAttributedTextRenderCacheEntry>()

    init() {
        cache.countLimit = 900
    }

    func result(for key: String) -> DynamicAttributedTextRenderResult? {
        cache.object(forKey: key as NSString)?.result
    }

    func set(_ result: DynamicAttributedTextRenderResult, for key: String) {
        cache.setObject(DynamicAttributedTextRenderCacheEntry(result: result), forKey: key as NSString)
    }
}

private final class DynamicAttributedTextRenderCacheEntry {
    let result: DynamicAttributedTextRenderResult

    init(result: DynamicAttributedTextRenderResult) {
        self.result = result
    }
}

struct DynamicAttributedTextRenderResult {
    let key: String
    let attributedString: NSAttributedString
    let missingImageURLs: [URL]
}
