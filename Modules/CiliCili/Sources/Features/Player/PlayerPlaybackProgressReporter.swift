import Combine
import Foundation

@MainActor
final class PlayerPlaybackProgressReporter: ObservableObject {
    private weak var clock: PlayerPlaybackClock?
    private var cancellable: AnyCancellable?
    private var report: ((TimeInterval) -> Void)?

    func start(clock: PlayerPlaybackClock, report: @escaping (TimeInterval) -> Void) {
        self.report = report
        guard self.clock !== clock else { return }

        cancellable?.cancel()
        self.clock = clock
        cancellable = clock.$currentTime
            .throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] time in
                self?.report?(time)
            }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        clock = nil
        report = nil
    }
}
