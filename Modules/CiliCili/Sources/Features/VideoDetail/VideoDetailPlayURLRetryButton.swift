import SwiftUI

struct VideoDetailPlayURLRetryButton: View {
    let title: String
    let systemImage: String
    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
