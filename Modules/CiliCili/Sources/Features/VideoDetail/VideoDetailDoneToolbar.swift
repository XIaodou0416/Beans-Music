import SwiftUI

struct VideoDetailDoneToolbar: ToolbarContent {
    let finish: () -> Void
    let accessibilityIdentifier: String

    init(finish: @escaping () -> Void, accessibilityIdentifier: String = "") {
        self.finish = finish
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("完成", action: finish)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }
}
