import SwiftUI

struct LiveRoomCardMetadataRow: View {
    let room: LiveRoom
    let title: String
    let anchorName: String
    let metadataText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StableVideoTitleText(
                title,
                style: .compactCard
            )
                .frame(minHeight: 36, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                AvatarRemoteImage(urlString: room.face, pixelSize: 48) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 14, height: 14)
                .clipShape(Circle())
                .mediaShadow(.subtle)

                Text(anchorName)
                    .appTypography(.compactAuthor, fallback: .caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if !metadataText.isEmpty {
                    Spacer(minLength: 6)

                    Text(metadataText)
                        .appTypography(.tertiaryMetadata, fallback: .caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}
