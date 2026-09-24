import CoreGraphics

nonisolated enum PlayerDoubleTapGesturePolicy {
    static func shouldTogglePlayback(locationX: CGFloat, width: CGFloat) -> Bool {
        guard width > 0 else { return false }
        return locationX >= 0 && locationX <= width
    }
}
