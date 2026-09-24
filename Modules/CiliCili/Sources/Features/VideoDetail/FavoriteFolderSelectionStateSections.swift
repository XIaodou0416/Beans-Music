import SwiftUI

struct FavoriteFolderSelectionLoadingSection: View {
    var body: some View {
        Section {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在读取收藏夹")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FavoriteFolderSelectionFailureSection: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        Section {
            ContentUnavailableView(
                "无法读取收藏夹",
                systemImage: "exclamationmark.circle",
                description: Text(message)
            )

            Button(action: retry) {
                Label("重试", systemImage: "arrow.clockwise")
            }
        }
    }
}

struct FavoriteFolderSelectionEmptySection: View {
    var body: some View {
        Section {
            ContentUnavailableView(
                "暂无收藏夹",
                systemImage: "folder",
                description: Text("请先在 B 站创建收藏夹。")
            )
        }
    }
}
