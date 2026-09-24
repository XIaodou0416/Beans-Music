import SwiftUI

struct SearchUserResultRow: View {
    let user: SearchUserItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SearchUserAvatar(urlString: user.face)

            VStack(alignment: .leading, spacing: 5) {
                SearchUserNameLine(user: user)

                SearchUserDescriptionText(user: user)
                    .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)

                Spacer(minLength: 0)

                SearchUserMetadataLine(user: user)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
    }
}

private struct SearchUserAvatar: View {
    let urlString: String?

    var body: some View {
        AvatarRemoteImage(urlString: urlString, pixelSize: 112) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
        .frame(width: 54, height: 54)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.quaternary, lineWidth: 0.7)
        }
    }
}

private struct SearchUserNameLine: View {
    let user: SearchUserItem

    var body: some View {
        HStack(spacing: 6) {
            Text(user.name)
                .appTypography(.author, fallback: .subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if user.isFollowing == true {
                Label("已关注", systemImage: "checkmark.circle.fill")
                    .appTypography(.badge, fallback: .caption2.weight(.semibold))
                    .foregroundStyle(.pink)
            }
        }
    }
}

private struct SearchUserDescriptionText: View {
    let user: SearchUserItem

    var body: some View {
        if let sign = user.sign, !sign.isEmpty {
            Text(sign)
                .appTypography(.settingsSubtitle, fallback: .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if let officialDescription = user.officialDescription, !officialDescription.isEmpty {
            Text(officialDescription)
                .appTypography(.settingsSubtitle, fallback: .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct SearchUserMetadataLine: View {
    let user: SearchUserItem

    var body: some View {
        HStack(spacing: 12) {
            SearchMetadataLabel(text: BiliFormatters.compactCount(user.fans), systemImage: "person.2")
            SearchMetadataLabel(text: BiliFormatters.compactCount(user.videos), systemImage: "play.square.stack")
        }
        .appTypography(.tertiaryMetadata, fallback: .caption2)
        .foregroundStyle(.tertiary)
    }
}
