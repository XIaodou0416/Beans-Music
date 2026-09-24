import SwiftUI

struct VideoDetailStatusBarBackdrop: View {
    let isHidden: Bool

    var body: some View {
        GeometryReader { proxy in
            if !isHidden {
                Color.black
                    .frame(height: proxy.safeAreaInsets.top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
