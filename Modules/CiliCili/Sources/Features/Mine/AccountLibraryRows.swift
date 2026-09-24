import SwiftUI

struct LibraryEmptyRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }
}
