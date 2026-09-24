import SwiftUI

struct LiveRoomCardCover: View {
    let coverURL: URL?
    let fallbackCoverURL: URL?
    let avatarCoverFallbackURL: URL?

    var body: some View {
        Color.gray.opacity(0.14)
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                coverImage
            }
    }

    private var coverImage: some View {
        CachedRemoteImage(
            url: coverURL,
            fallbackURL: fallbackCoverURL,
            targetPixelSize: 420,
            animatesAppearance: false
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            coverFallbackPlaceholder
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var coverFallbackPlaceholder: some View {
        if let avatarCoverFallbackURL {
            CachedRemoteImage(
                url: avatarCoverFallbackURL,
                targetPixelSize: 420,
                animatesAppearance: false
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                coverPlaceholderBase
            }
        } else {
            coverPlaceholderBase
        }
    }

    private var coverPlaceholderBase: some View {
        Color.gray.opacity(0.14)
            .overlay {
                Image(systemName: "play.tv")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }
}
