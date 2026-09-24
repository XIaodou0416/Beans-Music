import SwiftUI

struct VideoDetailCoinSheetHost: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appThemeTintColor) private var appTintColor
    @ObservedObject var viewModel: VideoDetailViewModel
    @State private var selectedCoinCount = 1
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("已投 \(viewModel.interactionState.coinCount) / 2 枚")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("投币数量", selection: $selectedCoinCount) {
                    ForEach(availableCoinCounts, id: \.self) { count in
                        Text("\(count) 枚").tag(count)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 150)
                .clipped()
                .disabled(isSubmitting || availableCoinCounts.isEmpty)

                if let message = viewModel.interactionMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                Button(action: submit) {
                    Group {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Label("投 \(selectedCoinCount) 枚", systemImage: "bitcoinsign.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(appTintColor)
                .controlSize(.large)
                .disabled(isSubmitting || availableCoinCounts.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .navigationTitle("投币")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
        .onAppear {
            viewModel.interactionMessage = nil
            normalizeSelection()
        }
        .onChange(of: remainingCoinCount) { _, _ in
            normalizeSelection()
        }
    }

    private var remainingCoinCount: Int {
        max(0, 2 - viewModel.interactionState.coinCount)
    }

    private var availableCoinCounts: [Int] {
        guard remainingCoinCount > 0 else { return [] }
        return Array(1...remainingCoinCount)
    }

    private func normalizeSelection() {
        selectedCoinCount = min(max(selectedCoinCount, 1), max(remainingCoinCount, 1))
    }

    private func submit() {
        guard !isSubmitting, availableCoinCounts.contains(selectedCoinCount) else { return }
        let coinCount = selectedCoinCount
        isSubmitting = true
        Task { @MainActor in
            let succeeded = await viewModel.addCoin(count: coinCount)
            isSubmitting = false
            if succeeded {
                Haptics.success()
                dismiss()
            }
        }
    }
}
