import SwiftUI

struct CommentSheetToolbarConfiguration {
    let onDismiss: () -> Void
    let onRefresh: () -> Void
}

private struct CommentSheetToolbarConfigurationKey: EnvironmentKey {
    static let defaultValue = CommentSheetToolbarConfiguration(onDismiss: {}, onRefresh: {})
}

extension EnvironmentValues {
    var commentSheetToolbarConfiguration: CommentSheetToolbarConfiguration {
        get { self[CommentSheetToolbarConfigurationKey.self] }
        set { self[CommentSheetToolbarConfigurationKey.self] = newValue }
    }
}

private struct CommentSheetPresentation: ViewModifier {
    @State private var selectedDetent: PresentationDetent = .medium
    let onDismiss: () -> Void
    let onRefresh: () -> Void

    func body(content: Content) -> some View {
        content
            .presentationDetents([.medium, .large], selection: $selectedDetent)
            .presentationContentInteraction(.resizes)
            .presentationDragIndicator(.visible)
            .environment(
                \.commentSheetToolbarConfiguration,
                CommentSheetToolbarConfiguration(onDismiss: onDismiss, onRefresh: onRefresh)
            )
    }
}

extension View {
    func commentSheetPresentation(
        onDismiss: @escaping () -> Void = {},
        onRefresh: @escaping () -> Void = {}
    ) -> some View {
        modifier(CommentSheetPresentation(onDismiss: onDismiss, onRefresh: onRefresh))
    }
}
