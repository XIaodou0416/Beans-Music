import SwiftUI

struct VideoDetailInitialPlayerPlaceholderBackButtonLayer: View {
    let action: () -> Void

    var body: some View {
        VideoDetailPlayerBackButton(action: action)
            .padding(.top, 10)
            .padding(.leading, 10)
    }
}
