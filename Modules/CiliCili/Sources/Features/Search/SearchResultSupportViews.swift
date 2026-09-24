import SwiftUI

struct SearchMetadataLabel: View {
    let text: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if !text.isEmpty, text != "-" {
            Label(text, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
    }
}

struct SearchSoftPill: View {
    let text: String
    let tint: Color

    init(_ text: String, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

struct SearchImagePlaceholder: View {
    let systemImage: String

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .overlay {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }
}
