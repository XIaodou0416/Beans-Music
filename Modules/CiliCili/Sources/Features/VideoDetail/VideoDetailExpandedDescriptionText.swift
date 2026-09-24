import SwiftUI
import UIKit

struct VideoDetailExpandedDescriptionText: View {
    let descriptionText: String

    var body: some View {
        BiliLinkedText(
            descriptionText,
            font: UIFont.preferredFont(forTextStyle: .caption1),
            textColor: .secondary
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .commentCopyContextMenu(text: descriptionText, title: "复制简介")
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
