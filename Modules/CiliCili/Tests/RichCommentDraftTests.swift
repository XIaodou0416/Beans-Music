import SwiftUI
import XCTest

@testable import CiliCiliKit

@MainActor
final class RichCommentDraftTests: XCTestCase {
    func testTextViewDelegateAllowsNativeIMEReplacementAndSyncsCommittedChineseText() {
        var draft = RichCommentDraft()
        let coordinator = RichCommentTextView.Coordinator(
            draft: Binding(
                get: { draft },
                set: { draft = $0 }
            ),
            onFocusChange: { _ in },
            onHeightChange: { _ in }
        )
        let textView = RichCommentUIKitTextView()
        textView.delegate = coordinator

        XCTAssertTrue(
            coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: 0, length: 0),
                replacementText: "你"
            )
        )

        textView.attributedText = NSAttributedString(
            string: "你好",
            attributes: [
                .font: textView.font ?? UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label
            ]
        )
        textView.selectedRange = NSRange(location: 2, length: 0)
        coordinator.textViewDidChange(textView)

        XCTAssertEqual(draft.serializedMessage, "你好")
        XCTAssertEqual(draft.selection, RichCommentSelection(NSRange(location: 2, length: 0)))
    }

    func testRichDraftSerializesTextAndEmotesSeparatelyFromDisplayText() {
        let draft = RichCommentDraft(elements: [
            .text("你好"),
            .emote("[doge]"),
            .text("世界")
        ])

        XCTAssertEqual(draft.displayText, "你好\u{FFFC}世界")
        XCTAssertEqual(draft.serializedMessage, "你好[doge]世界")
        XCTAssertTrue(draft.hasContent)
    }

    func testRichDraftInsertsAtSelectionAndRemovesAnEmoteAsOneUnit() {
        var draft = RichCommentDraft(elements: [
            .text("前"),
            .emote("[doge]"),
            .text("后")
        ])
        draft.selection = RichCommentSelection(NSRange(location: 1, length: 0))

        let inserted = draft.replacing(draft.selection!.nsRange, with: [.text("中")])
        XCTAssertEqual(inserted.serializedMessage, "前中[doge]后")

        let removed = inserted.replacing(NSRange(location: 2, length: 1), with: [])
        XCTAssertEqual(removed.serializedMessage, "前中后")
    }

    func testRichDraftRemovesItsOnlyEmote() {
        let draft = RichCommentDraft(elements: [.emote("[doge]")])

        let removed = draft.replacing(NSRange(location: 0, length: 1), with: [])

        XCTAssertTrue(removed.elements.isEmpty)
        XCTAssertEqual(removed.displayText, "")
        XCTAssertEqual(removed.serializedMessage, "")
    }

    func testRichDraftRejectsImageOnlySubmissionBecauseExistingAPIRequiresMessage() {
        let image = RichCommentImageDraft(sourceIdentifier: "photo-1", data: Data([1, 2, 3]))
        let draft = RichCommentDraft(images: [image])

        XCTAssertTrue(draft.hasContent)
        XCTAssertFalse(draft.canSubmitWithCurrentAPI)
    }
}
