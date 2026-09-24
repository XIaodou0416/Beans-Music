import SwiftUI

/// Shared owner avatar used by video and live playback detail pages.
struct PlaybackDetailOwnerAvatar: View {
    let owner: VideoOwner?
    let fallbackURLString: String?
    let side: CGFloat
    let pixelSize: Int

    init(
        owner: VideoOwner?,
        fallbackURLString: String? = nil,
        side: CGFloat,
        pixelSize: Int = 112
    ) {
        self.owner = owner
        self.fallbackURLString = fallbackURLString
        self.side = side
        self.pixelSize = pixelSize
    }

    var body: some View {
        if let owner, owner.mid > 0 {
            VideoOwnerRouteLink(owner: owner) {
                avatarImage(urlString: owner.face?.normalizedBiliURL())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("打开 \(owner.name) 的主页")
        } else {
            avatarImage(urlString: fallbackURLString?.normalizedBiliURL())
                .opacity(fallbackURLString == nil ? 0.58 : 1)
                .accessibilityLabel("UP主头像")
        }
    }

    private func avatarImage(urlString: String?) -> some View {
        PlaybackDetailOwnerAvatarImage(
            urlString: urlString,
            side: side,
            pixelSize: pixelSize
        )
    }
}

private struct PlaybackDetailOwnerAvatarImage: View {
    @Environment(\.colorScheme) private var colorScheme

    let urlString: String?
    let side: CGFloat
    let pixelSize: Int

    var body: some View {
        AvatarRemoteImage(urlString: urlString, pixelSize: pixelSize) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(outerStrokeColor, lineWidth: 1)
        }
        .overlay {
            Circle()
                .inset(by: 1)
                .strokeBorder(innerStrokeColor, lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.24), radius: 5, x: 0, y: 2.2)
        .shadow(color: .black.opacity(0.10), radius: 1.2, x: 0, y: 0.6)
        .frame(width: side, height: side)
        .contentShape(Circle())
    }

    private var outerStrokeColor: Color {
        switch colorScheme {
        case .dark:
            return .white.opacity(0.22)
        default:
            return .black.opacity(0.12)
        }
    }

    private var innerStrokeColor: Color {
        switch colorScheme {
        case .dark:
            return .white.opacity(0.12)
        default:
            return .white.opacity(0.46)
        }
    }
}
