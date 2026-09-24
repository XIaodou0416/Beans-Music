import SwiftUI
import UIKit

@MainActor
enum CommentCopyAction {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

private struct CommentCopyContextMenu: ViewModifier {
    let text: String?
    let title: String

    func body(content: Content) -> some View {
        if let copyText = text?.commentCopyText {
            content.contextMenu {
                Button {
                    CommentCopyAction.copy(copyText)
                } label: {
                    Label(title, systemImage: "doc.on.doc")
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func commentCopyContextMenu(text: String?, title: String) -> some View {
        modifier(CommentCopyContextMenu(text: text, title: title))
    }
}

private extension String {
    var commentCopyText: String? {
        let value = removingHTMLTags()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
