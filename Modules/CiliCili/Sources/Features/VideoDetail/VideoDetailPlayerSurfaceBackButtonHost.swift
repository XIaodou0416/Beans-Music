import SwiftUI

struct VideoDetailPlayerSurfaceBackButtonHost: View {
    let action: () -> Void
    var usesGlass = true

    var body: some View {
        VideoDetailPlayerBackButton(action: action, usesGlass: usesGlass)
    }
}
