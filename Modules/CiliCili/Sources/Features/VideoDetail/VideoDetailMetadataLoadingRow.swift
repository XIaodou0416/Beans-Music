import SwiftUI

struct VideoDetailMetadataLoadingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            SkeletonBlock(width: 72, height: 11, shape: .capsule)
            SkeletonBlock(width: 84, height: 11, shape: .capsule)
            SkeletonBlock(width: 58, height: 11, shape: .capsule)
            Spacer(minLength: 0)
        }
        .frame(height: 24, alignment: .center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
