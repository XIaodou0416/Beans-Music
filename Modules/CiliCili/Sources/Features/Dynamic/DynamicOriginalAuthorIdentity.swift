import SwiftUI

struct DynamicOriginalAuthorIdentity: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let author: DynamicAuthor

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "quote.opening")
                .font(.caption2.weight(.bold))
                .foregroundStyle(appTintColor)

            Text("转发自")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("@\(author.name ?? "Unknown")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}
