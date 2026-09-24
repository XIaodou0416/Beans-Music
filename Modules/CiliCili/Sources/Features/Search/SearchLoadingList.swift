import SwiftUI

struct SearchLoadingList: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                SearchLoadingContent(scope: .comprehensive)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.immediately)
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Color(.systemBackground))
        .nativeTopScrollEdgeEffect()
    }
}
