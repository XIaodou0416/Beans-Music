import UIKit

@MainActor
enum PlaybackNetworkDiagnosticsCopyAction {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
