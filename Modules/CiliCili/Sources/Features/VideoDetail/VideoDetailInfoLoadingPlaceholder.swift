import SwiftUI

struct VideoDetailInfoLoadingPlaceholder: View {
    let titleText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VideoDetailInfoTitleSkeleton()
            } else {
                VideoDetailInfoTitleText(text: titleText, isExpanded: false)
            }

            VideoDetailMetadataLoadingRow()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
