import SwiftUI

enum PlayerNativeProgressScrubCalculator {
    static func progress(locationX: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(locationX / width), 0), 1)
    }
}
