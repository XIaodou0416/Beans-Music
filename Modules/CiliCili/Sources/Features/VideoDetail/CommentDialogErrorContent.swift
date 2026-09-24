import SwiftUI

struct CommentDialogErrorContent: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        CommentErrorView(message: message, retry: retry)
            .padding(16)
    }
}
