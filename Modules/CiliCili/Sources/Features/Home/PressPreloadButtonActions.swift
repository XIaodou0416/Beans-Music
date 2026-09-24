import Foundation

struct PressPreloadButtonActions {
    let onPress: () -> Void

    func handlePressedChange(_ isPressed: Bool) {
        guard isPressed else { return }
        onPress()
    }
}
