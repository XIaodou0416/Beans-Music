import SwiftUI

struct UploaderFollowButton: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let owner: VideoOwner
    @ObservedObject var viewModel: UploaderViewModel

    var body: some View {
        Group {
            if viewModel.isFollowing {
                Button(action: toggleFollow) {
                    label
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: toggleFollow) {
                    label
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(appTintColor)
        .disabled(viewModel.isMutatingFollow || owner.mid <= 0)
    }

    private var label: some View {
        HStack(spacing: 6) {
            if viewModel.isMutatingFollow {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: viewModel.isFollowing ? "checkmark" : "plus")
                    .font(.caption.weight(.bold))
            }

            Text(viewModel.isFollowing ? "已关注" : "关注")
                .font(.caption.weight(.semibold))
        }
        .frame(minWidth: 62)
    }

    private func toggleFollow() {
        Task {
            let didSucceed = await viewModel.toggleFollow()
            if didSucceed {
                Haptics.success()
            } else {
                Haptics.light()
            }
        }
    }
}
