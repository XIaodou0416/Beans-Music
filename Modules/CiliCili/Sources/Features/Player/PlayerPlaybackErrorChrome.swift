import SwiftUI

struct PlayerPlaybackErrorChrome: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.black.opacity(0.72))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ui.player.error")
    }
}
