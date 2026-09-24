import SwiftUI

struct InitialPageMenuPlaceholder: View {
    let pageCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("分P")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if let pageCount {
                    Text("\(pageCount) P")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                SkeletonBlock(width: 28, height: 28, shape: .circle)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<min(max(pageCount ?? 4, 2), 6), id: \.self) { _ in
                        SkeletonBlock(width: 124, height: 54, shape: .rounded(12))
                    }
                }
            }
            .scrollDisabled(true)
            .frame(height: 54)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
