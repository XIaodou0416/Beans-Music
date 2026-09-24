import SwiftUI

enum MineOverlayRoute: Hashable {
    case accountMessages
    case multiAccountSettings
    case history
    case favorites
    case watchLater
    case interfaceSettings
    case homeAndSearchSettings
    case playbackSettings
    case contentFilterSettings
    case privacySettings

    var isSettingsRoute: Bool {
        switch self {
        case .interfaceSettings, .homeAndSearchSettings, .playbackSettings, .contentFilterSettings,
             .privacySettings, .multiAccountSettings:
            true
        case .accountMessages, .history, .favorites, .watchLater:
            false
        }
    }
}

struct MineOverlayNavigationButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(_ action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                label()
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
    }
}
