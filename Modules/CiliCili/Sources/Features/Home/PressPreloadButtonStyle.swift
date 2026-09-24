import SwiftUI

struct PressPreloadButtonStyle: ButtonStyle {
    let actions: PressPreloadButtonActions

    init(onPress: @escaping () -> Void) {
        actions = PressPreloadButtonActions(onPress: onPress)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.94 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                actions.handlePressedChange(isPressed)
            }
    }
}
