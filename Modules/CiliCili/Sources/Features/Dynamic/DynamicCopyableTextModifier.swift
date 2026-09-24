import SwiftUI
import UIKit

struct DynamicCopyableTextModifier: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let copyText {
            content.contextMenu {
                Button {
                    UIPasteboard.general.string = copyText
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
            }
        } else {
            content
        }
    }

    private var copyText: String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension View {
    func dynamicCopyableText(_ text: String?) -> some View {
        modifier(DynamicCopyableTextModifier(text: text))
    }
}
