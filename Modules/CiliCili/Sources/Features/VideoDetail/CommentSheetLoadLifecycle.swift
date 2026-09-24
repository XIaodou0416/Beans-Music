import SwiftUI

private struct CommentSheetLoadLifecycleModifier: ViewModifier {
    let load: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content
            .task {
                await load()
            }
    }
}

extension View {
    func commentSheetLoadLifecycle(
        load: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(CommentSheetLoadLifecycleModifier(load: load))
    }
}
