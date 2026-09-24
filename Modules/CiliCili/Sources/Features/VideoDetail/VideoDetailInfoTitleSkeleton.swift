import SwiftUI

struct VideoDetailInfoTitleSkeleton: View {
    var body: some View {
        SkeletonBlock(height: 18, shape: .rounded(5))
            .accessibilityHidden(true)
    }
}
