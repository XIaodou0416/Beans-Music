import SwiftUI
import UIKit

struct VideoDetailInfoTitleText: View {
    let text: String
    let isExpanded: Bool

    var body: some View {
        PlaybackDetailTitleText(
            text: text,
            lineLimit: isExpanded ? nil : 1
        )
    }
}
