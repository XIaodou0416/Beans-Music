import SwiftUI

struct InitialCommentsSection: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("评论")
                    .font(.headline)

                Spacer()

                HStack(spacing: 4) {
                    Text("最热")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(appTintColor.opacity(0.14))
                        .foregroundStyle(appTintColor)
                        .clipShape(Capsule())
                    Text("最新")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, CommentSectionStyle.plain.horizontalPadding)

            CommentsSkeletonContent(rowCount: 4, horizontalPadding: CommentSectionStyle.plain.horizontalPadding)
        }
        .padding(.vertical, 10)
        .allowsHitTesting(false)
    }
}
