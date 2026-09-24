import SwiftUI

struct UploaderContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct UploaderContentWidthReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: UploaderContentWidthPreferenceKey.self, value: proxy.size.width)
        }
        .frame(height: 0)
    }
}
