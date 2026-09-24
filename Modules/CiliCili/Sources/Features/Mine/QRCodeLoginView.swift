import SwiftUI

struct QRCodeLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: MineViewModel
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                QRCodeLoginContent(
                    state: viewModel.qrLoginState,
                    refresh: refreshQRCodeLogin
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background(Color(.systemBackground))
            .hiddenInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.startQRCodeLogin()
        }
        .onChange(of: viewModel.qrLoginState) { _, state in
            guard case .succeeded = state else { return }
            dismissTask?.cancel()
            dismissTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                dismiss()
            }
        }
        .onDisappear {
            dismissTask?.cancel()
            viewModel.cancelQRCodeLogin()
        }
    }

    private func refreshQRCodeLogin() {
        Task {
            await viewModel.startQRCodeLogin()
        }
    }
}
