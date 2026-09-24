import SwiftUI

struct LiveFeedSkeletonList: View {
    var horizontalPadding: CGFloat = 16
    var topPadding: CGFloat = 10

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(0..<12, id: \.self) { _ in
                LiveRoomSkeletonCard()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, 22)
    }
}

struct LiveFeedFooter: View {
    let text: String
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}
