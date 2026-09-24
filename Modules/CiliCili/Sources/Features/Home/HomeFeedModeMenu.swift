import SwiftUI

struct HomeFeedModeMenu: View {
    let currentMode: HomeFeedMode
    let onSelectMode: (HomeFeedMode) -> Void

    var body: some View {
        Menu {
            ForEach(HomeFeedMode.allCases, id: \.self) { mode in
                Button {
                    onSelectMode(mode)
                } label: {
                    Label(mode.title, systemImage: currentMode == mode ? "checkmark" : mode.systemImage)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .tint(.primary)
        .accessibilityLabel("首页内容")
        .accessibilityValue(currentMode.title)
    }
}
