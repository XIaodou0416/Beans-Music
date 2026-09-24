import SwiftUI

struct DynamicCommentReplyAuthorLine: View {
    let comment: Comment
    let display: DynamicCommentRowDisplayModel
    let showsLike: Bool
    var avatarHeight: CGFloat = 36

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
            .frame(minHeight: avatarHeight, alignment: .topLeading)

            if showsLike {
                Spacer(minLength: 8)
                CommentLikeButton(comment: comment)
            }
        }
    }
}

struct DynamicCommentReplyBody: View {
    let comment: Comment
    let display: DynamicCommentRowDisplayModel

    var body: some View {
        DynamicCommentText(
            content: comment.content,
            font: .subheadline,
            textColor: .primary,
            emoteSize: 22,
            lineSpacing: 2,
            typographyRole: .commentBody
        )
        DynamicCommentImageGrid(images: display.pictures)
    }
}
