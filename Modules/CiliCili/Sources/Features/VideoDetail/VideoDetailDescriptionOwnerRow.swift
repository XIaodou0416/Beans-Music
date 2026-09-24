import SwiftUI

struct VideoDescriptionOwnerRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let owner: VideoOwner?
    let fanCountText: String
    let isFollowing: Bool
    let isMutatingInteraction: Bool
    let toggleFollow: () -> Void

    var body: some View {
        let canOpenUploader = (owner?.mid ?? 0) > 0

        HStack(spacing: 10) {
            if let owner, canOpenUploader {
                VideoOwnerRouteLink(owner: owner) {
                    VideoDescriptionOwnerIdentity(
                        owner: owner,
                        fanCountText: fanCountText,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                VideoDescriptionOwnerIdentity(
                    owner: owner,
                    fanCountText: fanCountText,
                    showsChevron: false
                )
            }

            Spacer(minLength: 8)

            Button(action: toggleFollow) {
                Text(isFollowing ? "已关注" : "+ 关注")
                    .font(.caption.weight(.bold))
                    .frame(minWidth: 58)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isFollowing ? Color(.tertiarySystemFill) : appTintColor.opacity(0.12))
                    .foregroundStyle(isFollowing ? Color.secondary : appTintColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canOpenUploader || isMutatingInteraction)
        }
    }
}
