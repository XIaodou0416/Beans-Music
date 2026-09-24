import SwiftUI

struct UploaderSignatureText: View {
    let sign: String?

    var body: some View {
        if let sign, !sign.isEmpty {
            Text(sign)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct UploaderFollowMessage: View {
    let message: String?
    let isFollowing: Bool

    var body: some View {
        if let message, !message.isEmpty {
            Label(message, systemImage: isFollowing ? "checkmark.circle" : "info.circle")
                .font(.caption)
                .foregroundStyle(isFollowing ? Color.pink : Color.secondary)
        }
    }
}

struct UploaderProfileStatusMessage: View {
    let state: LoadingState

    var body: some View {
        if case .failed(let message) = state {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct UploaderStatsRow: View {
    @ObservedObject var viewModel: UploaderViewModel
    let card: UploaderCard?

    var body: some View {
        HStack(spacing: 14) {
            UploaderStatItem(title: "粉丝", value: viewModel.followerCount ?? card?.fans)
            UploaderStatItem(title: "关注", value: viewModel.followingCount ?? card?.attention)
            UploaderStatItem(title: "获赞", value: viewModel.likeCount)
            UploaderStatItem(title: "投稿", value: viewModel.archiveCount ?? loadedVideoCount)
        }
    }

    private var loadedVideoCount: Int? {
        viewModel.videos.isEmpty ? nil : viewModel.videos.count
    }
}

private struct UploaderStatItem: View {
    let title: String
    let value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(BiliFormatters.compactCount(value))
                .font(.subheadline.weight(.bold))

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
