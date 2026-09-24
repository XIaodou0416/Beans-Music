import SwiftUI

struct VideoDetailRelatedHeader: View {
    let isLoading: Bool

    var body: some View {
        HStack(spacing: VideoDetailRelatedStyle.headerSpacing) {
            Text("相关推荐")
                .font(.headline)

            Spacer()

            if isLoading {
                NativeLoadingIndicator()
                    .controlSize(.small)
                    .tint(.secondary)
            }
        }
    }
}
