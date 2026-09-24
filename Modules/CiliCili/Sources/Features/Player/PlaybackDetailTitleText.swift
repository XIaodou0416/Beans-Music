import SwiftUI

/// Shared primary title treatment for playback detail pages.
struct PlaybackDetailTitleText: View {
    let text: String
    let lineLimit: Int?
    let typographyRole: AppTypography.Role

    init(
        text: String,
        lineLimit: Int? = 1,
        typographyRole: AppTypography.Role = .videoDetailTitle
    ) {
        self.text = text
        self.lineLimit = lineLimit
        self.typographyRole = typographyRole
    }

    var body: some View {
        Text(text)
            .appTypography(typographyRole, fallback: .callout.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
