import UIKit

@MainActor
final class BeansOrientationLock {
    static let shared = BeansOrientationLock()

    private(set) var mask: UIInterfaceOrientationMask = .portrait

    func setEmbeddedPlayerOrientation() {
        mask = .allButUpsideDown
        updateSceneGeometry()
    }

    func restoreDefaultOrientation() {
        mask = .portrait
        updateSceneGeometry()
    }

    private func updateSceneGeometry() {
        UIViewController.attemptRotationToDeviceOrientation()
        guard #available(iOS 16.0, *) else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            guard scene.activationState == .foregroundActive else { continue }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

@MainActor
final class BeansAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        BeansOrientationLock.shared.mask
    }
}
