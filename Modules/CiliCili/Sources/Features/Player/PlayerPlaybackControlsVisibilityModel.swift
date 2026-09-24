import Combine
import SwiftUI

@MainActor
final class PlayerPlaybackControlsVisibilityModel: ObservableObject {
    @Published var isVisible = true
    @Published private(set) var opacity = 1.0
    @Published private(set) var acceptsHitTesting = true

    private var isAutoHideSuspended = false
    private var autoHideTask: Task<Void, Never>?
    private var hideCompletionTask: Task<Void, Never>?
    private let hideAnimationDuration: UInt64 = 350_000_000

    func syncSecondaryControlsPresentation(
        _ isPresented: Bool,
        showsPlaybackControls: Bool,
        isLayoutTransitioning: Bool
    ) {
        isAutoHideSuspended = isPresented
        if isPresented {
            cancelAutoHide()
            show(scheduleAutoHide: false, showsPlaybackControls: showsPlaybackControls)
        } else {
            scheduleAutoHide(
                showsPlaybackControls: showsPlaybackControls,
                isLayoutTransitioning: isLayoutTransitioning
            )
        }
    }

    func showAndSchedule(
        showsPlaybackControls: Bool,
        isLayoutTransitioning: Bool
    ) {
        show(
            scheduleAutoHide: true,
            animated: !isLayoutTransitioning,
            showsPlaybackControls: showsPlaybackControls,
            isLayoutTransitioning: isLayoutTransitioning
        )
    }

    func markInteraction(
        keepsVisible: Bool = false,
        showsPlaybackControls: Bool,
        isLayoutTransitioning: Bool
    ) {
        show(
            scheduleAutoHide: !keepsVisible,
            animated: !isLayoutTransitioning,
            showsPlaybackControls: showsPlaybackControls,
            isLayoutTransitioning: isLayoutTransitioning
        )
        if keepsVisible {
            cancelAutoHide()
        }
    }

    func toggle(
        showsPlaybackControls: Bool,
        isLayoutTransitioning: Bool
    ) {
        guard showsPlaybackControls else { return }
        if isVisible, opacity > 0.5 {
            hide(animated: true)
        } else {
            showAndSchedule(
                showsPlaybackControls: showsPlaybackControls,
                isLayoutTransitioning: isLayoutTransitioning
            )
        }
    }

    func hide(animated: Bool) {
        cancelAutoHide()
        hideCompletionTask?.cancel()
        let update = { self.opacity = 0 }
        if animated {
            isVisible = true
            acceptsHitTesting = true
            withAnimation(.default, update)
            hideCompletionTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: self?.hideAnimationDuration ?? 350_000_000)
                guard let self, !Task.isCancelled else { return }
                self.isVisible = false
                self.acceptsHitTesting = false
                self.hideCompletionTask = nil
            }
        } else {
            update()
            isVisible = false
            acceptsHitTesting = false
            hideCompletionTask = nil
        }
    }

    private func cancelPendingHide() {
        hideCompletionTask?.cancel()
        hideCompletionTask = nil
    }

    private func showNow(animated: Bool) {
        cancelPendingHide()
        isVisible = true
        acceptsHitTesting = true
        let update = { self.opacity = 1 }
        if animated {
            withAnimation(.default, update)
        } else {
            update()
        }
    }

    func show(
        scheduleAutoHide: Bool,
        animated: Bool = true,
        showsPlaybackControls: Bool,
        isLayoutTransitioning: Bool = false
    ) {
        guard showsPlaybackControls else { return }
        showNow(animated: animated)
        if scheduleAutoHide {
            self.scheduleAutoHide(
                showsPlaybackControls: showsPlaybackControls,
                isLayoutTransitioning: isLayoutTransitioning
            )
        }
    }

    func scheduleAutoHide(
        showsPlaybackControls: Bool,
        isLayoutTransitioning: Bool
    ) {
        guard showsPlaybackControls, isVisible else { return }
        guard !isLayoutTransitioning else { return }
        guard !isAutoHideSuspended else { return }
        cancelAutoHide()
        autoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard !self.isAutoHideSuspended else { return }
            self.autoHideTask = nil
            self.hide(animated: true)
        }
    }

    func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    deinit {
        autoHideTask?.cancel()
        hideCompletionTask?.cancel()
    }
}
