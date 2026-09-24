import SwiftUI

struct HomeFeedWidthReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: HomeFeedWidthPreferenceKey.self, value: proxy.size.width)
        }
        .frame(height: 0)
    }
}
