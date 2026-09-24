import SwiftUI

struct PlaybackDetailLoadedStatePage<Value, LoadedContent: View, InitialContent: View>: View {
    let value: Value?
    let performanceContext: PlaybackDetailPerformanceContext?
    let loadedContent: (Value) -> LoadedContent
    let initialContent: () -> InitialContent
    @State private var keepsInitialContent = true

    init(
        _ value: Value?,
        performanceContext: PlaybackDetailPerformanceContext? = nil,
        @ViewBuilder loadedContent: @escaping (Value) -> LoadedContent,
        @ViewBuilder initialContent: @escaping () -> InitialContent
    ) {
        self.value = value
        self.performanceContext = performanceContext
        self.loadedContent = loadedContent
        self.initialContent = initialContent
    }

    var body: some View {
        ZStack {
            if keepsInitialContent {
                initialContent()
                    .opacity(isLoaded ? 0 : 1)
                    .allowsHitTesting(!isLoaded)
                    .accessibilityHidden(isLoaded)
                    .onAppear {
                        mark(.initialContentAppeared)
                    }
                    .onDisappear {
                        guard isLoaded else { return }
                        mark(.initialContentRemoved)
                    }
            }

            if let value {
                loadedContent(value)
                    .zIndex(1)
                    .onAppear {
                        mark(.loadedContentAppeared)
                    }
            }
        }
        .task(id: isLoaded) {
            guard isLoaded else {
                keepsInitialContent = true
                return
            }
            await Task.yield()
            keepsInitialContent = false
        }
    }

    private var isLoaded: Bool {
        value != nil
    }

    private func mark(_ milestone: PlaybackDetailPerformanceMilestone) {
        guard let performanceContext else { return }
        PlaybackDetailPerformanceMonitor.shared.mark(milestone, context: performanceContext)
    }
}
