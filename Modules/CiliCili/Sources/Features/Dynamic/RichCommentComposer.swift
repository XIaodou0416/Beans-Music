import PhotosUI
import SwiftUI
import UIKit

enum RichCommentDraftElement: Equatable, Sendable {
    case text(String)
    case emote(String)

    var displayString: String {
        switch self {
        case .text(let value):
            return value
        case .emote:
            return "\u{FFFC}"
        }
    }

    var serializedString: String {
        switch self {
        case .text(let value), .emote(let value):
            return value
        }
    }
}

struct RichCommentSelection: Equatable, Sendable {
    let location: Int
    let length: Int

    init(_ range: NSRange) {
        location = range.location
        length = range.length
    }

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

struct RichCommentImageDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceIdentifier: String?
    let data: Data

    init(id: UUID = UUID(), sourceIdentifier: String?, data: Data) {
        self.id = id
        self.sourceIdentifier = sourceIdentifier
        self.data = data
    }
}

struct RichCommentDraft: Equatable, Sendable {
    var elements: [RichCommentDraftElement]
    var selection: RichCommentSelection?
    var images: [RichCommentImageDraft]
    var replyTarget: DynamicCommentComposerTarget?

    init(
        elements: [RichCommentDraftElement] = [],
        selection: RichCommentSelection? = nil,
        images: [RichCommentImageDraft] = [],
        replyTarget: DynamicCommentComposerTarget? = nil
    ) {
        self.elements = Self.normalized(elements)
        self.selection = selection
        self.images = images
        self.replyTarget = replyTarget
    }

    var displayText: String {
        elements.map(\.displayString).joined()
    }

    var serializedMessage: String {
        elements.map(\.serializedString).joined()
    }

    var containsEmote: Bool {
        elements.contains {
            if case .emote = $0 { return true }
            return false
        }
    }

    var hasContent: Bool {
        !serializedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || containsEmote
            || !images.isEmpty
    }

    var canSubmitWithCurrentAPI: Bool {
        !serializedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func replacing(_ range: NSRange, with replacement: [RichCommentDraftElement]) -> RichCommentDraft {
        let displayLength = displayText.utf16.count
        let start = min(max(range.location, 0), displayLength)
        let end = min(max(start + max(range.length, 0), start), displayLength)
        var result = [RichCommentDraftElement]()
        var cursor = 0
        var didInsert = false

        for element in elements {
            let elementLength = element.displayString.utf16.count
            let elementStart = cursor
            let elementEnd = cursor + elementLength

            if end <= elementStart {
                if !didInsert {
                    Self.append(replacement, to: &result)
                    didInsert = true
                }
                Self.append(element, to: &result)
            } else if start >= elementEnd {
                Self.append(element, to: &result)
            } else {
                let localStart = max(start - elementStart, 0)
                let localEnd = min(end - elementStart, elementLength)
                if case .text(let value) = element {
                    let nsValue = value as NSString
                    if localStart > 0 {
                        Self.append(.text(nsValue.substring(with: NSRange(location: 0, length: localStart))), to: &result)
                    }
                    if !didInsert {
                        Self.append(replacement, to: &result)
                        didInsert = true
                    }
                    if localEnd < elementLength {
                        Self.append(
                            .text(nsValue.substring(from: localEnd)),
                            to: &result
                        )
                    }
                } else if !didInsert {
                    Self.append(replacement, to: &result)
                    didInsert = true
                }
            }
            cursor = elementEnd
        }

        if !didInsert {
            Self.append(replacement, to: &result)
        }

        var updated = self
        updated.elements = Self.normalized(result)
        return updated
    }

    func insertingText(_ text: String, at selection: RichCommentSelection?) -> RichCommentDraft {
        let range = selection?.nsRange ?? NSRange(location: displayText.utf16.count, length: 0)
        return replacing(range, with: text.isEmpty ? [] : [.text(text)])
    }

    private static func normalized(_ elements: [RichCommentDraftElement]) -> [RichCommentDraftElement] {
        var result = [RichCommentDraftElement]()
        append(elements, to: &result)
        return result
    }

    private static func append(_ elements: [RichCommentDraftElement], to result: inout [RichCommentDraftElement]) {
        elements.forEach { append($0, to: &result) }
    }

    private static func append(_ element: RichCommentDraftElement, to result: inout [RichCommentDraftElement]) {
        guard case .text(let value) = element,
              let last = result.last,
              case .text(let existing) = last
        else {
            result.append(element)
            return
        }
        result[result.count - 1] = .text(existing + value)
    }
}

struct RichCommentComposerPresenter: UIViewControllerRepresentable {
    @Binding var target: DynamicCommentComposerTarget?
    let draft: (DynamicCommentComposerTarget) -> Binding<RichCommentDraft>
    let api: BiliAPIClient
    let submit: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> PresenterViewController {
        let controller = PresenterViewController()
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        return controller
    }

    func updateUIViewController(
        _ controller: PresenterViewController,
        context: Context
    ) {
        context.coordinator.update(
            target: target,
            draft: draft,
            api: api,
            submit: submit,
            presenter: controller,
            targetBinding: $target
        )
    }

    final class PresenterViewController: UIViewController {}

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        private weak var presentedController: UIHostingController<AnyView>?
        private var presentedTargetID: String?

        func update(
            target: DynamicCommentComposerTarget?,
            draft: @escaping (DynamicCommentComposerTarget) -> Binding<RichCommentDraft>,
            api: BiliAPIClient,
            submit: @escaping (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void,
            presenter: UIViewController,
            targetBinding: Binding<DynamicCommentComposerTarget?>
        ) {
            guard let target else {
                guard let presentedController else { return }
                self.presentedController = nil
                presentedTargetID = nil
                presentedController.dismiss(animated: true)
                return
            }

            let rootView = AnyView(
                RichCommentComposerPresentationView(
                    onBackgroundTap: {
                        targetBinding.wrappedValue = nil
                    }
                ) {
                    RichCommentComposerView(
                        draft: draft(target),
                        target: target,
                        api: api,
                        submit: submit,
                        onDismiss: {
                            targetBinding.wrappedValue = nil
                        }
                    )
                }
            )

            if let presentedController {
                presentedTargetID = target.id
                presentedController.rootView = rootView
                return
            }

            let host = UIHostingController(rootView: rootView)
            host.view.backgroundColor = .clear
            host.view.isOpaque = false
            host.modalPresentationStyle = .overFullScreen
            host.modalTransitionStyle = .coverVertical
            host.presentationController?.delegate = self
            presentedController = host
            presentedTargetID = target.id
            presenter.present(host, animated: true)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            presentedController = nil
            presentedTargetID = nil
        }
    }
}

private struct RichCommentComposerPresentationView<Content: View>: View {
    let onBackgroundTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

enum RichCommentInputMode: Equatable {
    case keyboard
    case emotes
}

private extension NSAttributedString.Key {
    static let richCommentEmoteToken = NSAttributedString.Key("cc.bili.richCommentEmoteToken")
}

struct RichCommentTextView: UIViewRepresentable {
    @Binding var draft: RichCommentDraft
    @Binding var isFocused: Bool
    let inputMode: RichCommentInputMode
    let inputViewHeight: CGFloat
    let emotes: [BiliInlineEmote]
    let dynamicTypeSize: DynamicTypeSize
    let onFocusChange: (Bool) -> Void
    let onEditorTap: () -> Void
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            draft: $draft,
            onFocusChange: onFocusChange,
            onHeightChange: onHeightChange
        )
    }

    func makeUIView(context: Context) -> RichCommentUIKitTextView {
        let textView = RichCommentUIKitTextView()
        textView.delegate = context.coordinator
        textView.onTap = onEditorTap
        textView.updateTypingAttributes()
        context.coordinator.applyIfNeeded(draft: draft, to: textView, emotes: emotes)
        textView.configureInputView(
            mode: inputMode,
            height: inputViewHeight,
            emotes: emotes
        )
        textView.setFocused(isFocused)
        return textView
    }

    func updateUIView(_ textView: RichCommentUIKitTextView, context: Context) {
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.onHeightChange = onHeightChange
        textView.onTap = onEditorTap
        textView.font = .preferredFont(forTextStyle: .body)
        textView.updateTypingAttributes()
        textView.configureInputView(
            mode: inputMode,
            height: inputViewHeight,
            emotes: emotes
        )
        context.coordinator.applyIfNeeded(draft: draft, to: textView, emotes: emotes)
        textView.setFocused(isFocused)
        textView.reportHeightIfNeeded()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var draft: RichCommentDraft
        var onFocusChange: (Bool) -> Void
        var onHeightChange: (CGFloat) -> Void
        private var isApplyingDraft = false
        private var renderedElements: [RichCommentDraftElement] = []
        private var renderedFontPointSize: CGFloat?
        private var imageTask: Task<Void, Never>?

        init(
            draft: Binding<RichCommentDraft>,
            onFocusChange: @escaping (Bool) -> Void,
            onHeightChange: @escaping (CGFloat) -> Void
        ) {
            _draft = draft
            self.onFocusChange = onFocusChange
            self.onHeightChange = onHeightChange
        }

        deinit {
            imageTask?.cancel()
        }

        func applyIfNeeded(
            draft: RichCommentDraft,
            to textView: RichCommentUIKitTextView,
            emotes: [BiliInlineEmote]
        ) {
            guard textView.markedTextRange == nil else { return }
            let font = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
            var effectiveDraft = draft
            let renderedText = renderedElements.map { $0.displayString }.joined()
            if draft.elements.isEmpty,
               !renderedElements.isEmpty,
               textView.text == renderedText {
                effectiveDraft.elements = renderedElements
                effectiveDraft.selection = RichCommentSelection(textView.selectedRange)
                let recoveredDraft = effectiveDraft
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.draft != recoveredDraft else { return }
                    self.draft = recoveredDraft
                }
            }

            let shouldReplaceText = renderedElements != effectiveDraft.elements
                || textView.text != effectiveDraft.displayText
                || renderedFontPointSize != font.pointSize
            if shouldReplaceText {
                isApplyingDraft = true
                textView.attributedText = Self.attributedString(
                    for: effectiveDraft.elements,
                    font: font,
                    emotes: emotes
                )
                let selection = effectiveDraft.selection?.nsRange
                    ?? NSRange(location: textView.text.utf16.count, length: 0)
                textView.selectedRange = Self.clamped(selection, to: textView.text.utf16.count)
                isApplyingDraft = false
                renderedElements = effectiveDraft.elements
                renderedFontPointSize = font.pointSize
                loadMissingImages(in: textView, elements: effectiveDraft.elements, emotes: emotes)
            } else if let selection = effectiveDraft.selection?.nsRange,
                      textView.selectedRange != selection {
                textView.selectedRange = Self.clamped(selection, to: textView.text.utf16.count)
            }
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard !isApplyingDraft,
                  let richTextView = textView as? RichCommentUIKitTextView
            else { return false }

            // Let UITextView own marked text. Returning false here interrupts the
            // IME composition buffer, so pinyin is committed as Latin characters.
            if text.isEmpty,
               range.length == 0,
               range.location > 0,
               isEmoteAttachment(at: range.location - 1, in: richTextView) {
                deleteBackward(in: richTextView)
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingDraft,
                  textView.markedTextRange == nil,
                  let richTextView = textView as? RichCommentUIKitTextView
            else { return }

            let elements = Self.elements(from: richTextView.attributedText)
            var updatedDraft = draft
            updatedDraft.elements = elements
            updatedDraft.selection = RichCommentSelection(richTextView.selectedRange)
            renderedElements = elements
            renderedFontPointSize = richTextView.font?.pointSize
            if updatedDraft != draft {
                draft = updatedDraft
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingDraft, textView.markedTextRange == nil else { return }
            let selection = RichCommentSelection(textView.selectedRange)
            if draft.selection != selection {
                draft.selection = selection
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            onFocusChange(false)
        }

        func insertEmote(_ token: String, into textView: RichCommentUIKitTextView) {
            guard let emote = textView.availableEmotes.first(where: { $0.token == token }) else { return }
            let range = draft.selection?.nsRange
                ?? textView.selectedRange
            applyReplacement(
                range,
                with: [.emote(emote.token)],
                selectionLocation: range.location + 1,
                to: textView
            )
            textView.becomeFirstResponder()
        }

        func deleteBackward(in textView: RichCommentUIKitTextView) {
            let selection = textView.selectedRange
            guard selection.length > 0 || selection.location > 0 else { return }

            let range: NSRange
            if selection.length > 0 {
                range = selection
            } else {
                range = (textView.text as NSString).rangeOfComposedCharacterSequence(
                    at: selection.location - 1
                )
            }
            applyReplacement(range, with: [], selectionLocation: range.location, to: textView)
            textView.becomeFirstResponder()
        }

        func reportHeight(_ height: CGFloat) {
            onHeightChange(height)
        }

        private func applyReplacement(
            _ range: NSRange,
            with replacement: [RichCommentDraftElement],
            selectionLocation: Int,
            to textView: RichCommentUIKitTextView
        ) {
            var updatedDraft = draft.replacing(range, with: replacement)
            updatedDraft.selection = RichCommentSelection(NSRange(location: selectionLocation, length: 0))
            if updatedDraft.elements.isEmpty {
                renderedElements = []
            }
            draft = updatedDraft
            applyIfNeeded(draft: updatedDraft, to: textView, emotes: textView.availableEmotes)
        }

        private func isEmoteAttachment(at location: Int, in textView: RichCommentUIKitTextView) -> Bool {
            guard location >= 0, location < textView.attributedText.length else { return false }
            guard textView.attributedText.attribute(
                .attachment,
                at: location,
                effectiveRange: nil
            ) is NSTextAttachment else { return false }
            return textView.attributedText.attribute(
                .richCommentEmoteToken,
                at: location,
                effectiveRange: nil
            ) as? String != nil
        }

        private static func elements(from attributedText: NSAttributedString) -> [RichCommentDraftElement] {
            guard attributedText.length > 0 else { return [] }

            var elements = [RichCommentDraftElement]()
            attributedText.enumerateAttributes(
                in: NSRange(location: 0, length: attributedText.length)
            ) { attributes, range, _ in
                if let token = attributes[.richCommentEmoteToken] as? String {
                    elements.append(.emote(token))
                } else {
                    let text = attributedText.attributedSubstring(from: range).string
                    if !text.isEmpty {
                        elements.append(.text(text))
                    }
                }
            }
            return RichCommentDraft(elements: elements).elements
        }

        private func loadMissingImages(
            in textView: RichCommentUIKitTextView,
            elements: [RichCommentDraftElement],
            emotes: [BiliInlineEmote]
        ) {
            imageTask?.cancel()
            let missing = elements.compactMap { element -> (String, URL)? in
                guard case .emote(let token) = element,
                      let emote = emotes.first(where: { $0.token == token }),
                      let urlString = emote.displayURL,
                      let url = URL(string: urlString),
                      BiliEmoteImageStore.shared.cachedImage(for: url) == nil
                else { return nil }
                return (token, url)
            }
            guard !missing.isEmpty else { return }

            imageTask = Task { @MainActor [weak self, weak textView] in
                for (token, url) in missing {
                    guard !Task.isCancelled,
                          let image = await BiliEmoteImageStore.shared.image(for: url),
                          let self,
                          let textView
                    else { return }
                    self.updateAttachmentImage(image, token: token, in: textView)
                }
            }
        }

        private func updateAttachmentImage(_ image: UIImage, token: String, in textView: RichCommentUIKitTextView) {
            let range = NSRange(location: 0, length: textView.attributedText.length)
            textView.textStorage.enumerateAttribute(
                .richCommentEmoteToken,
                in: range
            ) { value, attributeRange, _ in
                guard value as? String == token,
                      let attachment = textView.attributedText.attribute(
                        .attachment,
                        at: attributeRange.location,
                        effectiveRange: nil
                      ) as? NSTextAttachment
                else { return }
                attachment.image = image
                textView.layoutManager.invalidateLayout(forCharacterRange: attributeRange, actualCharacterRange: nil)
                textView.setNeedsDisplay()
            }
        }

        private static func attributedString(
            for elements: [RichCommentDraftElement],
            font: UIFont,
            emotes: [BiliInlineEmote]
        ) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.label
            ]
            for element in elements {
                switch element {
                case .text(let text):
                    result.append(NSAttributedString(string: text, attributes: baseAttributes))
                case .emote(let token):
                    let emote = emotes.first(where: { $0.token == token })
                    let size = font.lineHeight
                    let ratio = (emote?.width ?? 1) / max(emote?.height ?? 1, 1)
                    let attachment = NSTextAttachment()
                    if let urlString = emote?.displayURL,
                       let url = URL(string: urlString),
                       let image = BiliEmoteImageStore.shared.cachedImage(for: url) {
                        attachment.image = image
                    } else {
                        attachment.image = BiliEmoteImageStore.shared.placeholderImage(size: size)
                    }
                    attachment.bounds = CGRect(
                        x: 0,
                        y: (font.capHeight - size) / 2,
                        width: max(size * ratio, size),
                        height: size
                    )
                    let attachmentLocation = result.length
                    result.append(NSAttributedString(attachment: attachment))
                    result.addAttributes(
                        [
                            .richCommentEmoteToken: token,
                            .font: font
                        ],
                        range: NSRange(location: attachmentLocation, length: 1)
                    )
                }
            }
            result.addAttribute(
                .paragraphStyle,
                value: NSParagraphStyle.default,
                range: NSRange(location: 0, length: result.length)
            )
            return result
        }

        private static func clamped(_ range: NSRange, to length: Int) -> NSRange {
            let location = min(max(range.location, 0), length)
            let available = max(length - location, 0)
            return NSRange(location: location, length: min(max(range.length, 0), available))
        }
    }
}

final class RichCommentUIKitTextView: UITextView {
    var onTap: (() -> Void)?
    var availableEmotes = [BiliInlineEmote]()

    private var emoteInputView: RichCommentEmoteInputView?
    private var inputMode: RichCommentInputMode = .keyboard
    private var wantsFocus = false
    private var lastInputViewHeight: CGFloat = 0
    private var reportedHeight: CGFloat = 0
    private var measuredKeyboardHeight: CGFloat = 0

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        backgroundColor = .clear
        font = .preferredFont(forTextStyle: .body)
        textColor = .label
        tintColor = .label
        adjustsFontForContentSizeCategory = true
        textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textContainer?.lineFragmentPadding = 0
        isScrollEnabled = true
        showsVerticalScrollIndicator = false
        accessibilityLabel = "评论内容"
        accessibilityIdentifier = "dynamic.comment.composer.editor"
    }

    required init?(coder: NSCoder) {
        nil
    }

    func updateTypingAttributes() {
        typingAttributes = [
            .font: font ?? UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: textColor ?? UIColor.label
        ]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportHeightIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if window != nil {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardFrameChanged(_:)),
                name: UIResponder.keyboardDidChangeFrameNotification,
                object: nil
            )
        }
        setFocused(wantsFocus)
    }

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard let window,
              let value = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        else { return }
        let screenFrame = value.cgRectValue
        let keyboardFrame = window.coordinateSpace.convert(
            screenFrame,
            from: window.screen.coordinateSpace
        )
        let height = max(0, window.bounds.maxY - keyboardFrame.minY)
        if height > 0 {
            measuredKeyboardHeight = max(measuredKeyboardHeight, height)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        wantsFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onTap?()
            if !self.isFirstResponder {
                self.becomeFirstResponder()
            }
        }
    }

    func setFocused(_ isFocused: Bool) {
        wantsFocus = isFocused
        guard window != nil else { return }
        if isFocused, !isFirstResponder {
            becomeFirstResponder()
        } else if !isFocused, isFirstResponder {
            resignFirstResponder()
        }
    }

    func configureInputView(
        mode: RichCommentInputMode,
        height: CGFloat,
        emotes: [BiliInlineEmote]
    ) {
        availableEmotes = emotes
        let resolvedHeight = max(height, max(measuredKeyboardHeight, 216))
        var shouldReload = inputMode != mode
        if mode == .emotes {
            let inputView = emoteInputView ?? RichCommentEmoteInputView(
                frame: CGRect(x: 0, y: 0, width: max(bounds.width, 320), height: resolvedHeight),
                inputViewStyle: .keyboard
            )
            inputView.configure(
                height: resolvedHeight,
                emotes: emotes,
                insertEmote: { [weak self] token in
                    guard let self,
                          let coordinator = self.delegate as? RichCommentTextView.Coordinator
                    else { return }
                    coordinator.insertEmote(token, into: self)
                },
                deleteBackward: { [weak self] in
                    guard let self,
                          let coordinator = self.delegate as? RichCommentTextView.Coordinator
                    else { return }
                    coordinator.deleteBackward(in: self)
                }
            )
            emoteInputView = inputView
            self.inputView = inputView
            shouldReload = shouldReload || abs(lastInputViewHeight - resolvedHeight) > 0.5
            lastInputViewHeight = resolvedHeight
        } else {
            inputView = nil
        }
        inputMode = mode
        if shouldReload, isFirstResponder {
            reloadInputViews()
        }
    }

    func reportHeightIfNeeded() {
        let fittingSize = sizeThatFits(CGSize(width: max(bounds.width, 1), height: .greatestFiniteMagnitude))
        let height = min(max(fittingSize.height, 44), 132)
        guard abs(height - reportedHeight) > 0.5 else { return }
        reportedHeight = height
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let coordinator = self.delegate as? RichCommentTextView.Coordinator
            else { return }
            coordinator.reportHeight(height)
        }
    }
}

final class RichCommentEmoteInputView: UIInputView {
    private let hostingController = UIHostingController(rootView: AnyView(EmptyView()))
    private var panelHeight: CGFloat = 216
    private var bottomSafeAreaInset: CGFloat = 0
    private var currentEmotes = [BiliInlineEmote]()
    private var insertEmote: ((String) -> Void)?
    private var deleteBackward: (() -> Void)?

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: panelHeight)
    }

    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        allowsSelfSizing = true
        backgroundColor = .clear
        hostingController.view.backgroundColor = .clear
        hostingController.view.insetsLayoutMarginsFromSafeArea = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: panelHeight)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        let inset = safeAreaInsets.bottom
        guard abs(bottomSafeAreaInset - inset) > 0.5 else { return }
        bottomSafeAreaInset = inset
        updatePickerRootView()
    }

    func configure(
        height: CGFloat,
        emotes: [BiliInlineEmote],
        insertEmote: @escaping (String) -> Void,
        deleteBackward: @escaping () -> Void
    ) {
        if abs(panelHeight - height) > 0.5 {
            panelHeight = height
            invalidateIntrinsicContentSize()
        }
        currentEmotes = emotes
        self.insertEmote = insertEmote
        self.deleteBackward = deleteBackward
        updatePickerRootView()
    }

    private func updatePickerRootView() {
        hostingController.rootView = AnyView(
            DynamicInlineCommentEmotePicker(
                emotes: currentEmotes,
                bottomSafeAreaInset: bottomSafeAreaInset,
                onSelect: insertEmote ?? { _ in },
                onDelete: deleteBackward
            )
            .ignoresSafeArea(.container, edges: .bottom)
        )
    }
}

struct RichCommentAttachmentStrip: View {
    @Binding var images: [RichCommentImageDraft]
    let isUploading: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { image in
                    ZStack(alignment: .topTrailing) {
                        if let uiImage = UIImage(data: image.data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 68, height: 68)
                                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.secondary.opacity(0.12))
                                .frame(width: 68, height: 68)
                        }

                        if isUploading {
                            ProgressView()
                                .controlSize(.small)
                                .padding(4)
                                .background(.regularMaterial, in: Circle())
                        } else {
                            Button {
                                images.removeAll { $0.id == image.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.65))
                                    .font(.body)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .accessibilityLabel("移除图片")
                            .accessibilityIdentifier("dynamic.comment.composer.removeImage")
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 72)
        .accessibilityIdentifier("dynamic.comment.composer.attachments")
    }
}

struct RichCommentComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var draft: RichCommentDraft
    let target: DynamicCommentComposerTarget
    let api: BiliAPIClient
    let submit: (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void
    let onDismiss: (() -> Void)?

    @State private var inputMode: RichCommentInputMode = .keyboard
    @State private var isEditorFocused = false
    @State private var editorHeight: CGFloat = 44
    @State private var emotes = [BiliInlineEmote]()
    @State private var selectedPhotos = [PhotosPickerItem]()
    @State private var pendingSelectedPhotos = [PhotosPickerItem]()
    @State private var showsPhotoPicker = false
    @State private var isLoadingImages = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var submitTask: Task<Void, Never>?

    private enum Limits {
        static let maximumImageCount = 9
    }

    private enum ControlLayout {
        static let size: CGFloat = 32
    }

    init(
        draft: Binding<RichCommentDraft>,
        target: DynamicCommentComposerTarget,
        api: BiliAPIClient,
        submit: @escaping (DynamicCommentComposerTarget, String, [DynamicCommentImage]?) async throws -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self._draft = draft
        self.target = target
        self.api = api
        self.submit = submit
        self.onDismiss = onDismiss
    }

    private var sendableMessage: String {
        draft.serializedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        draft.canSubmitWithCurrentAPI
            && !isSubmitting
            && !isLoadingImages
    }

    private let resolvedInputViewHeight: CGFloat = 216

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let authorName = target.authorName,
               !authorName.isEmpty {
                Label("回复 @\(authorName)", systemImage: "arrowshape.turn.up.left")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            RichCommentTextView(
                draft: $draft,
                isFocused: $isEditorFocused,
                inputMode: inputMode,
                inputViewHeight: resolvedInputViewHeight,
                emotes: emotes,
                dynamicTypeSize: dynamicTypeSize,
                onFocusChange: { isEditorFocused = $0 },
                onEditorTap: focusEditor,
                onHeightChange: { editorHeight = $0 }
            )
            .frame(height: min(max(editorHeight, 44), 132))
            .accessibilityIdentifier("dynamic.comment.composer.editor")

            if !draft.images.isEmpty {
                RichCommentAttachmentStrip(
                    images: $draft.images,
                    isUploading: isSubmitting
                )
            } else if isLoadingImages {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取图片")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("dynamic.comment.composer.imageLoading")
            }

            HStack(spacing: 12) {
                Button(action: toggleEmotes) {
                    Image(systemName: inputMode == .emotes ? "keyboard" : "face.smiling")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: ControlLayout.size, height: ControlLayout.size)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .accessibilityLabel(inputMode == .emotes ? "切换至系统键盘" : "选择表情")
                .accessibilityIdentifier("dynamic.comment.composer.emote")

                Button {
                    showsPhotoPicker = true
                } label: {
                    Image(systemName: "photo")
                        .frame(width: ControlLayout.size, height: ControlLayout.size)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .disabled(draft.images.count >= Limits.maximumImageCount || isSubmitting)
                .accessibilityLabel("添加图片")
                .accessibilityIdentifier("dynamic.comment.composer.photo")

                Spacer(minLength: 0)

                Button(action: submitDraft) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: ControlLayout.size, height: ControlLayout.size)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .frame(width: ControlLayout.size, height: ControlLayout.size)
                    }
                }
                .modifier(RichCommentSendButtonAppearance(isEnabled: canSend, tint: appTintColor))
                .controlSize(.small)
                .disabled(!canSend)
                .accessibilityLabel(isSubmitting ? "正在发送评论" : "发送评论")
                .accessibilityIdentifier("dynamic.comment.composer.send")
            }
            .font(.body)
            .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .biliGlassEffect(interactive: true, in: .rect(cornerRadius: 24, style: .continuous))
        .padding(12)
        .presentationBackground(Color.clear)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
        .task {
            if draft.replyTarget == nil {
                draft.replyTarget = target.authorName == nil ? nil : target
            }
            await Task.yield()
            guard !Task.isCancelled else { return }
            isEditorFocused = true
            emotes = (try? await api.fetchCommentEmotes()) ?? []
        }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            pendingSelectedPhotos = items
            if !showsPhotoPicker {
                processPendingPhotos()
            }
        }
        .onChange(of: showsPhotoPicker) { _, isPresented in
            guard !isPresented else { return }
            processPendingPhotos()
        }
        .photosPicker(
            isPresented: $showsPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: max(0, Limits.maximumImageCount - draft.images.count),
            matching: .images,
            preferredItemEncoding: .current
        )
        .onDisappear {
            photoLoadTask?.cancel()
            submitTask?.cancel()
            isEditorFocused = false
        }
        .alert("评论发送失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请稍后重试")
        }
    }

    private func focusEditor() {
        guard !isSubmitting else { return }
        withOptionalAnimation {
            if inputMode != .keyboard {
                inputMode = .keyboard
            }
            isEditorFocused = true
        }
    }

    private func toggleEmotes() {
        guard !isSubmitting else { return }
        withOptionalAnimation {
            inputMode = inputMode == .emotes ? .keyboard : .emotes
            isEditorFocused = true
        }
    }

    private func withOptionalAnimation(_ action: () -> Void) {
        if reduceMotion {
            action()
        } else {
            withAnimation(.smooth, action)
        }
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoLoadTask?.cancel()
        let knownIdentifiers = Set(draft.images.compactMap(\.sourceIdentifier))
        let newItems = items.filter { item in
            guard let identifier = item.itemIdentifier else { return true }
            return !knownIdentifiers.contains(identifier)
        }
        guard !newItems.isEmpty else {
            selectedPhotos = []
            return
        }

        isLoadingImages = true
        photoLoadTask = Task { @MainActor in
            defer {
                isLoadingImages = false
                selectedPhotos = []
            }

            for item in newItems {
                guard !Task.isCancelled else { return }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        errorMessage = "无法读取所选图片"
                        continue
                    }
                    guard let normalizedData = await Self.normalizedImageData(data) else {
                        errorMessage = "无法处理所选图片"
                        continue
                    }
                    guard draft.images.count < Limits.maximumImageCount else { return }
                    var updatedDraft = draft
                    updatedDraft.images.append(RichCommentImageDraft(
                        sourceIdentifier: item.itemIdentifier,
                        data: normalizedData
                    ))
                    draft = updatedDraft
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            focusEditor()
        }
    }

    private func processPendingPhotos() {
        let items = pendingSelectedPhotos.isEmpty ? selectedPhotos : pendingSelectedPhotos
        guard !items.isEmpty else { return }
        pendingSelectedPhotos = []
        loadSelectedPhotos(items)
    }

    private static func normalizedImageData(_ data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard let image = UIImage(data: data) else { return nil }
                return image.jpegData(compressionQuality: 0.88) ?? data
            }
        }.value
    }

    private func submitDraft() {
        guard canSend else { return }
        let submissionTarget = draft.replyTarget ?? target
        let message = sendableMessage
        isSubmitting = true
        errorMessage = nil
        submitTask = Task { @MainActor in
            defer { isSubmitting = false }
            do {
                var pictures = [DynamicCommentImage]()
                for image in draft.images {
                    try Task.checkCancellation()
                    pictures.append(try await api.uploadDynamicCommentImage(image.data))
                }
                try await submit(submissionTarget, message, pictures.isEmpty ? nil : pictures)
                draft = RichCommentDraft()
                isEditorFocused = false
                Haptics.success()
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct RichCommentSendButtonAppearance: ViewModifier {
    let isEnabled: Bool
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(tint)
                .foregroundStyle(.white)
        } else {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(.primary)
        }
    }
}
