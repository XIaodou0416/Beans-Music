import SwiftUI

private struct DynamicCommentHitAreaVisualizationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var dynamicCommentHitAreaVisualizationEnabled: Bool {
        get { self[DynamicCommentHitAreaVisualizationKey.self] }
        set { self[DynamicCommentHitAreaVisualizationKey.self] = newValue }
    }
}

enum DynamicCommentHitAreaKind: Equatable {
    case reply
    case control

    fileprivate var color: Color {
        switch self {
        case .reply:
            .pink.opacity(0.18)
        case .control:
            .purple.opacity(0.22)
        }
    }

    fileprivate var cornerRadius: CGFloat {
        switch self {
        case .reply:
            8
        case .control:
            10
        }
    }
}

extension View {
    func dynamicCommentHitArea(_ kind: DynamicCommentHitAreaKind) -> some View {
        modifier(DynamicCommentHitAreaVisualization(kind: kind))
    }
}

private struct DynamicCommentHitAreaVisualization: ViewModifier {
    @Environment(\.dynamicCommentHitAreaVisualizationEnabled) private var isEnabled
    let kind: DynamicCommentHitAreaKind

    func body(content: Content) -> some View {
        content
            .background {
                if isEnabled, kind == .reply {
                    RoundedRectangle(cornerRadius: kind.cornerRadius, style: .continuous)
                        .fill(kind.color)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if isEnabled, kind == .control {
                    RoundedRectangle(cornerRadius: kind.cornerRadius, style: .continuous)
                        .fill(kind.color)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}
