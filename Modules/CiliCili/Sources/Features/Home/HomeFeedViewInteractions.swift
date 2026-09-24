import SwiftUI

extension View {
    @ViewBuilder
    func homeLoadMoreTask(
        if shouldAttachTask: Bool,
        id: String,
        action: @escaping () async -> Void
    ) -> some View {
        if shouldAttachTask {
            task(id: id) {
                await action()
            }
        } else {
            self
        }
    }
}
