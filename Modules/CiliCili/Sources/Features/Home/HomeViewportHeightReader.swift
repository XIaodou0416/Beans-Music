import SwiftUI

struct HomeViewportHeightReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: HomeViewportHeightPreferenceKey.self, value: proxy.size.height)
        }
    }
}
