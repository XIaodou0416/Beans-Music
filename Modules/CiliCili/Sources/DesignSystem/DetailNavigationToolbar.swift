import SwiftUI

private enum DetailToolbarMetrics {
    static let avatarSide: CGFloat = 28
    static let followButtonMinWidth: CGFloat = 56
}

struct DetailNavigationOwnerLabel: View {
    let avatarURLString: String?
    let name: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 7) {
            DetailToolbarAvatar(urlString: avatarURLString)
                .fixedSize()

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.88)

                if let subtitle = displaySubtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .layoutPriority(2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([displayName, displaySubtitle].compactMap { $0 }.joined(separator: "，"))
    }

    private var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "UP主" : trimmedName
    }

    private var displaySubtitle: String? {
        guard let subtitle else { return nil }
        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSubtitle.isEmpty ? nil : trimmedSubtitle
    }
}

struct DetailToolbarAvatar: View {
    let urlString: String?

    var body: some View {
        AvatarRemoteImage(urlString: urlString, pixelSize: 72) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
        .frame(width: DetailToolbarMetrics.avatarSide, height: DetailToolbarMetrics.avatarSide)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color(.separator).opacity(0.18), lineWidth: 0.7)
        }
        .contentShape(Circle())
    }
}

struct DetailToolbarFollowButton: View {
    let isFollowing: Bool
    let isLoading: Bool
    let canFollow: Bool
    let action: () -> Void

    var body: some View {
        if isFollowing {
            button
                .foregroundStyle(.secondary)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 0.7)
                }
        } else {
            button
                .foregroundStyle(Color(red: 0.98, green: 0.22, blue: 0.43))
                .background {
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.98, green: 0.22, blue: 0.43).opacity(0.14))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color(red: 0.98, green: 0.22, blue: 0.43).opacity(0.20), lineWidth: 0.7)
                }
        }
    }

    private var button: some View {
        Button(action: action) {
            Text(isFollowing ? "已关注" : "关注")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .padding(.horizontal, isFollowing ? 8 : 10)
                .frame(minWidth: DetailToolbarMetrics.followButtonMinWidth)
                .frame(height: DetailToolbarMetrics.avatarSide)
        }
        .buttonStyle(.plain)
        .disabled(!canFollow || isLoading)
        .opacity((canFollow && !isLoading) ? 1 : 0.58)
        .accessibilityLabel(isFollowing ? "已关注" : "关注")
    }
}
