import SwiftUI

struct VideoDetailInteractionNotice: View {
    @ObservedObject var store: VideoDetailInteractionRenderStore
    @State private var visibleFallbackMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = visibleFallbackMessage, !message.isEmpty {
                VideoDetailNoticeLabel(message: message, systemImage: "sparkles.tv")
                    .transition(.opacity)
            }
            if let message = store.interactionMessage, !message.isEmpty {
                VideoDetailNoticeLabel(message: message, systemImage: "exclamationmark.circle")
            }
        }
        .onAppear {
            updateVisibleFallbackMessage(store.playbackFallbackMessage)
        }
        .onChange(of: store.playbackFallbackMessage) { _, message in
            updateVisibleFallbackMessage(message)
        }
        .task(id: visibleFallbackMessage) {
            guard let message = visibleFallbackMessage, !message.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard visibleFallbackMessage == message else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                visibleFallbackMessage = nil
            }
        }
    }

    private func updateVisibleFallbackMessage(_ message: String?) {
        guard let message, !message.isEmpty else {
            visibleFallbackMessage = nil
            return
        }
        withAnimation(.easeIn(duration: 0.18)) {
            visibleFallbackMessage = message
        }
    }
}
