import SwiftUI

struct LiveDanmakuDiagnosticsOverlay: View {
    @ObservedObject var store: LiveDanmakuDiagnosticsStore
    let usesLandscapeChrome: Bool

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                LiveDanmakuDiagnosticsHUD(
                    snapshot: store.snapshot,
                    isExpanded: usesLandscapeChrome
                )
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, usesLandscapeChrome ? 46 : 10)
        .padding(.leading, usesLandscapeChrome ? 18 : 8)
        .padding(.trailing, 8)
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
    }
}
