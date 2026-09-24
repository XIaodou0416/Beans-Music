import SwiftUI

struct DynamicFeedSkeletonScrollContent: View {
    var body: some View {
        ScrollView {
            DynamicFeedSkeletonList()
                .padding(.horizontal, 16)
                .padding(.top, 28)
        }
        .nativeTopScrollEdgeEffect()
    }
}

struct DynamicFeedSkeletonList: View {
    private let placeholderCount = 6

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<placeholderCount, id: \.self) { index in
                DynamicFeedSkeletonCard()
                    .allowsHitTesting(false)

                if index != placeholderCount - 1 {
                    Divider()
                        .padding(.leading, 66)
                }
            }
        }
    }
}

struct DynamicFeedErrorOverlay: View {
    @ObservedObject var viewModel: DynamicViewModel
    let isLoggedIn: Bool

    var body: some View {
        Group {
            if isLoggedIn,
               case .failed(let message) = viewModel.state,
               viewModel.items.isEmpty {
                ErrorStateView(title: "动态加载失败", message: message) {
                    Task { await viewModel.refresh() }
                }
                .background(.background.opacity(0.96))
            }
        }
    }
}

struct DynamicLoginEmptyState: View {
    var body: some View {
        EmptyStateView(
            title: "暂无动态",
            systemImage: "sparkles",
            message: "登录后会显示你关注 UP 的动态。"
        )
    }
}

struct DynamicFeedEmptyState: View {
    var body: some View {
        EmptyStateView(
            title: "暂无动态",
            systemImage: "sparkles",
            message: "登录后会显示你关注 UP 的动态。"
        )
    }
}
