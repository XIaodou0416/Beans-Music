import SwiftUI

enum BeansMotion {
    static let press = Animation.spring(response: 0.30, dampingFraction: 0.78, blendDuration: 0.08)
    static let tabSelection = Animation.spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0.12)
    static let appearance = Animation.spring(response: 0.48, dampingFraction: 0.88, blendDuration: 0.08)
    static let imageReveal = Animation.easeOut(duration: 0.28)
    static let trackSwap = Animation.spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.08)
    static let toast = Animation.spring(response: 0.40, dampingFraction: 0.82, blendDuration: 0.08)
    static let playerDismiss = Animation.spring(response: 0.52, dampingFraction: 0.90, blendDuration: 0.10)
}
