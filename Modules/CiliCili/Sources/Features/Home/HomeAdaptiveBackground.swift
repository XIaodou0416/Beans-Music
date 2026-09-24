import SwiftUI

extension HomeFeedLayout {
    var homeFeedBackground: Color {
        self == .borderedSingleColumn
            ? Color(.systemGroupedBackground)
            : Color(.systemBackground)
    }
}
