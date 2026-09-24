import SwiftUI

struct DynamicFeedItemsList: View {
    let api: BiliAPIClient
    @ObservedObject var viewModel: DynamicViewModel
    let items: [DynamicFeedItem]
    let contentWidth: CGFloat

    private var lastItemID: String? {
        items.last?.id
    }

    var body: some View {
        ForEach(items) { item in
            VStack(spacing: 0) {
                DynamicFeedCard(
                    item: item,
                    api: api,
                    contentWidth: contentWidth
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .dynamicLoadMoreTask(if: item.id == lastItemID, id: item.id) {
                    await viewModel.loadMoreIfNeeded(current: item)
                }

                if item.id != lastItemID {
                    Divider()
                        .padding(.leading, 66)
                }
            }
        }
    }
}

struct DynamicFeedFooter: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @ObservedObject var viewModel: DynamicViewModel

    var body: some View {
        Group {
            if viewModel.state.isLoading {
                DynamicFeedSkeletonCard()
                    .allowsHitTesting(false)
            } else if viewModel.hasMoreItems {
                Button {
                    Task { await viewModel.loadMore() }
                } label: {
                    Label("加载更多", systemImage: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(appTintColor)
                .padding(.top, 10)
            } else {
                Text("没有更多动态了")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
    }
}
