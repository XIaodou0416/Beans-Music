import SwiftUI

struct VideoDescriptionOwnerIdentity: View {
    let owner: VideoOwner?
    let fanCountText: String
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 10) {
            AvatarRemoteImage(urlString: owner?.face, pixelSize: 96) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(owner?.name ?? "Unknown")
                    .appTypography(.author, fallback: .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(fanCountText)
                    .appTypography(.metadata, fallback: .caption)
                    .foregroundStyle(.secondary)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
