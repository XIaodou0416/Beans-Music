import SwiftUI

struct DynamicFeedAuthorHeader: View {
    let authorOwner: VideoOwner?
    let avatarURLString: String?
    let authorName: String
    let publishTimeText: String

    var body: some View {
        HStack(spacing: 9) {
            if let authorOwner, authorOwner.mid > 0 {
                VideoOwnerRouteLink(owner: authorOwner) {
                    authorIdentity
                }
            } else {
                authorIdentity
            }

            Spacer(minLength: 10)

            if !publishTimeText.isEmpty {
                Text(publishTimeText)
                    .appTypography(.metadata, fallback: .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var authorIdentity: some View {
        HStack(spacing: 9) {
            AvatarRemoteImage(urlString: avatarURLString, pixelSize: 96) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .mediaShadow(.subtle)

            Text(authorName)
                .appTypography(.author, fallback: .subheadline.weight(.semibold))
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

extension DynamicFeedAuthorHeader {
    init(display: DynamicFeedCardDisplayModel) {
        self.init(
            authorOwner: display.authorOwner,
            avatarURLString: display.authorAvatarURLString,
            authorName: display.authorName,
            publishTimeText: display.publishTimeText
        )
    }
}
