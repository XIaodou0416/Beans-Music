import SwiftUI

struct DynamicCommentRowHeader: View {
    let comment: Comment
    let display: DynamicCommentRowDisplayModel

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                CommentAuthorIdentity(name: display.authorName, owner: display.authorOwner)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if !display.timeText.isEmpty {
                    Text(display.timeText)
                        .appTypography(.metadata, fallback: .caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 38, alignment: .topLeading)

            Spacer(minLength: 8)

            CommentLikeButton(comment: comment)
        }
    }
}
