import SwiftUI

struct VideoFeedStoryHeader: View {
    let display: VideoCardDisplayModel

    var body: some View {
        HStack(spacing: 9) {
            AvatarRemoteImage(urlString: display.avatarURLString, pixelSize: 64) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .mediaShadow(.subtle)

            Text(display.authorName)
                .appTypography(.author)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 10)

            Text(display.publishTimeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
    }
}
