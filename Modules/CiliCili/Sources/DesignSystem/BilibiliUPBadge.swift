import SwiftUI

struct BilibiliUPBadge: View {
    let size: CGFloat
    var color: Color = .secondary

    var body: some View {
        Image("BilibiliUPBadge")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
