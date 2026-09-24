import SwiftUI

struct DynamicCommentsHeader: View {
    let replyCount: Int?
    @Binding var selectedSort: CommentSort

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("全部评论")
                    .font(.headline.weight(.semibold))

                if let replyCount, replyCount > 0 {
                    Text(BiliFormatters.compactCount(replyCount))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("评论排序", selection: $selectedSort) {
                    ForEach(CommentSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 124)
                .controlSize(.small)
                .accessibilityLabel("评论排序")
            }
        }
    }
}
