import Combine
import SwiftUI
import UIKit

struct DanmakuOverlayView: UIViewRepresentable {
    fileprivate struct ConfigurationSignature: Equatable {
        let itemsRevision: Int
        let currentTimeBucket: Int?
        let isPlaying: Bool
        let playbackRateTenths: Int
        let isEnabled: Bool
        let hasPresentedPlayback: Bool
        let isLoadShedding: Bool
        let settings: DanmakuSettings
        let topInsetTenths: Int
        let bottomInsetTenths: Int

        init(
            itemsRevision: Int,
            currentTime: TimeInterval,
            usesExternalClock: Bool,
            isPlaying: Bool,
            playbackRate: Double,
            isEnabled: Bool,
            hasPresentedPlayback: Bool,
            isLoadShedding: Bool,
            settings: DanmakuSettings,
            topInset: CGFloat,
            bottomInset: CGFloat
        ) {
            self.itemsRevision = itemsRevision
            // When a PlayerPlaybackClock is bound, UIKit receives time ticks directly.
            // Without one, keep a coarse time bucket so live-style callers can resync.
            currentTimeBucket = usesExternalClock ? nil : Int(max(0, currentTime) * 2)
            self.isPlaying = isPlaying
            playbackRateTenths = Int((max(playbackRate, 0.1) * 10).rounded())
            self.isEnabled = isEnabled
            self.hasPresentedPlayback = hasPresentedPlayback
            self.isLoadShedding = isLoadShedding
            self.settings = settings.normalized
            topInsetTenths = Int((max(0, topInset) * 10).rounded())
            bottomInsetTenths = Int((max(0, bottomInset) * 10).rounded())
        }
    }

    let items: [DanmakuItem]
    let itemsRevision: Int
    let currentTime: TimeInterval
    let isPlaying: Bool
    let playbackRate: Double
    let isEnabled: Bool
    let hasPresentedPlayback: Bool
    let isLoadShedding: Bool
    let settings: DanmakuSettings
    let topInset: CGFloat
    let bottomInset: CGFloat
    let isLayoutTransitioning: Bool
    let playbackClock: PlayerPlaybackClock?
    let onPlaybackTime: ((TimeInterval, Bool) -> Void)?

    init(
        items: [DanmakuItem],
        itemsRevision: Int,
        currentTime: TimeInterval = 0,
        isPlaying: Bool,
        playbackRate: Double,
        isEnabled: Bool,
        hasPresentedPlayback: Bool,
        isLoadShedding: Bool = false,
        settings: DanmakuSettings,
        topInset: CGFloat,
        bottomInset: CGFloat,
        isLayoutTransitioning: Bool = false,
        playbackClock: PlayerPlaybackClock? = nil,
        onPlaybackTime: ((TimeInterval, Bool) -> Void)? = nil
    ) {
        self.items = items
        self.itemsRevision = itemsRevision
        self.currentTime = currentTime
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.isEnabled = isEnabled
        self.hasPresentedPlayback = hasPresentedPlayback
        self.isLoadShedding = isLoadShedding
        self.settings = settings
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.isLayoutTransitioning = isLayoutTransitioning
        self.playbackClock = playbackClock
        self.onPlaybackTime = onPlaybackTime
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> DanmakuAnimationOverlayView {
        let view = DanmakuAnimationOverlayView()
        view.setLayoutTransitioning(isLayoutTransitioning)
        let resolvedCurrentTime = playbackClock?.currentTime ?? currentTime
        let signature = configurationSignature(resolvedCurrentTime: resolvedCurrentTime)
        view.apply(
            items: items,
            itemsRevision: itemsRevision,
            currentTime: resolvedCurrentTime,
            isPlaying: isPlaying,
            playbackRate: playbackRate,
            isEnabled: isEnabled,
            hasPresentedPlayback: hasPresentedPlayback,
            isLoadShedding: isLoadShedding,
            settings: settings,
            topInset: topInset,
            bottomInset: bottomInset
        )
        context.coordinator.markApplied(signature)
        context.coordinator.bind(clock: playbackClock, uiView: view, onPlaybackTime: onPlaybackTime)
        return view
    }

    func updateUIView(_ uiView: DanmakuAnimationOverlayView, context: Context) {
        if isLayoutTransitioning {
            uiView.setLayoutTransitioning(true)
        }
        let resolvedCurrentTime = playbackClock?.currentTime ?? currentTime
        let signature = configurationSignature(resolvedCurrentTime: resolvedCurrentTime)
        if context.coordinator.shouldApply(signature) {
            uiView.apply(
                items: items,
                itemsRevision: itemsRevision,
                currentTime: resolvedCurrentTime,
                isPlaying: isPlaying,
                playbackRate: playbackRate,
                isEnabled: isEnabled,
                hasPresentedPlayback: hasPresentedPlayback,
                isLoadShedding: isLoadShedding,
                settings: settings,
                topInset: topInset,
                bottomInset: bottomInset
            )
            context.coordinator.markApplied(signature)
        }
        if !isLayoutTransitioning {
            uiView.setLayoutTransitioning(false)
        }
        context.coordinator.bind(clock: playbackClock, uiView: uiView, onPlaybackTime: onPlaybackTime)
    }

    private func configurationSignature(resolvedCurrentTime: TimeInterval) -> ConfigurationSignature {
        ConfigurationSignature(
            itemsRevision: itemsRevision,
            currentTime: resolvedCurrentTime,
            usesExternalClock: playbackClock != nil,
            isPlaying: isPlaying,
            playbackRate: playbackRate,
            isEnabled: isEnabled,
            hasPresentedPlayback: hasPresentedPlayback,
            isLoadShedding: isLoadShedding,
            settings: settings,
            topInset: topInset,
            bottomInset: bottomInset
        )
    }

    static func dismantleUIView(_ uiView: DanmakuAnimationOverlayView, coordinator: Coordinator) {
        coordinator.unbind()
        uiView.stop()
    }

    @MainActor
    final class Coordinator {
        private weak var boundClock: PlayerPlaybackClock?
        private var clockCancellable: AnyCancellable?
        private var onPlaybackTime: ((TimeInterval, Bool) -> Void)?
        private var lastReportedPlaybackSecond: Int?
        private var isLoadShedding = false
        private var lastAppliedSignature: ConfigurationSignature?

        fileprivate func shouldApply(_ signature: ConfigurationSignature) -> Bool {
            lastAppliedSignature != signature
        }

        fileprivate func markApplied(_ signature: ConfigurationSignature) {
            lastAppliedSignature = signature
        }

        func bind(
            clock: PlayerPlaybackClock?,
            uiView: DanmakuAnimationOverlayView,
            onPlaybackTime: ((TimeInterval, Bool) -> Void)?
        ) {
            self.onPlaybackTime = onPlaybackTime
            self.isLoadShedding = uiView.isLoadShedding
            guard boundClock !== clock else { return }

            clockCancellable?.cancel()
            boundClock = clock

            guard let clock else { return }
            uiView.synchronizePlaybackTime(clock.currentTime, force: true)
            reportPlaybackTime(clock.currentTime, force: true)
            clockCancellable = clock.$currentTime
                .removeDuplicates { abs($0 - $1) < 0.05 }
                .sink { [weak self, weak uiView] time in
                    uiView?.synchronizePlaybackTime(time)
                    self?.reportPlaybackTime(time)
                }
        }

        func unbind() {
            clockCancellable?.cancel()
            clockCancellable = nil
            boundClock = nil
            lastReportedPlaybackSecond = nil
            lastAppliedSignature = nil
            onPlaybackTime = nil
        }

        private func reportPlaybackTime(_ playbackTime: TimeInterval, force: Bool = false) {
            guard let onPlaybackTime else { return }
            let sanitizedTime = max(0, playbackTime)
            let secondBucket = Int(sanitizedTime.rounded(.down))
            guard force || lastReportedPlaybackSecond != secondBucket else { return }
            lastReportedPlaybackSecond = secondBucket
            onPlaybackTime(sanitizedTime, isLoadShedding)
        }
    }
}

final class DanmakuAnimationOverlayView: UIView {
    private struct ActiveEntry {
        let id: String
        let item: DanmakuItem
        let label: UILabel
        let completion: DanmakuAnimationCompletionDelegate?
        let createdAt: CFTimeInterval
        let animationGeneration: Int
        let scrollingTrajectory: ScrollingTrajectory?
    }

    private struct ScrollingTrajectory {
        let labelWidth: CGFloat
        let surfaceWidth: CGFloat
        let startX: CGFloat
        let endX: CGFloat
        let displayDuration: TimeInterval
    }

    private struct LaneState {
        let releaseTime: TimeInterval
        let itemWidth: CGFloat
    }

    private struct TextMeasurementKey: Hashable {
        let text: String
        let fontSizeTenths: Int
        let fontWeight: DanmakuFontWeightOption
    }

    private struct TimeBucket {
        let index: Int
        var items: [DanmakuItem]
    }

    private var items: [DanmakuItem] = []
    private var timeBuckets: [TimeBucket] = []
    private var settings: DanmakuSettings = .default
    private var currentTime: TimeInterval = 0
    private var isPlaying = false
    private var playbackRate: Double = 1
    private var isEnabled = true
    private var hasPresentedPlayback = false
    private(set) var isLoadShedding = false
    private var topInset: CGFloat = 0
    private var bottomInset: CGFloat = 0
    private var nextBucketIndex = 0
    private var nextBucketItemIndex = 0
    private var anchorPlaybackTime: TimeInterval = 0
    private var anchorHostTime = CACurrentMediaTime()
    private var displayLink: CADisplayLink?
    private var activeEntries: [String: ActiveEntry] = [:]
    private var reusableLabels: [UILabel] = []
    private var scrollingLaneStates: [Int: LaneState] = [:]
    private var textSizeCache: [TextMeasurementKey: CGSize] = [:]
    private var textSizeCacheOrder: [TextMeasurementKey] = []
    private var lastLayoutSize: CGSize = .zero
    private var activeAnimationSpeed: Float = 1
    private var lastItemsRevision = -1
    private var animationGeneration = 0
    private var layoutSettlingGeneration = 0
    private var isLayoutSettling = false
    private var isLayoutTransitioning = false
    private var needsLayoutRebuildAfterTransition = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        guard abs(size.width - lastLayoutSize.width) > 1 || abs(size.height - lastLayoutSize.height) > 1 else { return }
        if isLayoutTransitioning {
            needsLayoutRebuildAfterTransition = true
            return
        }
        lastLayoutSize = size
        beginLayoutSettling(animated: isPlaying)
        guard shouldRenderDanmaku else {
            clearActiveLabels()
            return
        }
        rebuildVisibleItemsAfterLayoutChange(
            at: effectivePlaybackTime(),
            animated: false
        )
        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    func setLayoutTransitioning(_ isTransitioning: Bool) {
        guard isLayoutTransitioning != isTransitioning else { return }
        isLayoutTransitioning = isTransitioning
        if isTransitioning {
            cancelLayoutSettling()
            return
        }
        guard needsLayoutRebuildAfterTransition else { return }
        needsLayoutRebuildAfterTransition = false
        lastLayoutSize = bounds.size
        // Keep active Core Animation instances intact. Rebuilding here restarts fixed
        // danmaku opacity and scrolling trajectories on the rotation completion frame.
        setNextSpawnPosition(after: effectivePlaybackTime())
        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    func apply(
        items newItems: [DanmakuItem],
        itemsRevision newItemsRevision: Int,
        currentTime newCurrentTime: TimeInterval,
        isPlaying newIsPlaying: Bool,
        playbackRate newPlaybackRate: Double,
        isEnabled newIsEnabled: Bool,
        hasPresentedPlayback newHasPresentedPlayback: Bool,
        isLoadShedding newIsLoadShedding: Bool,
        settings newSettings: DanmakuSettings,
        topInset newTopInset: CGFloat,
        bottomInset newBottomInset: CGFloat
    ) {
        let normalizedRate = max(newPlaybackRate, 0.1)
        let sanitizedTime = max(0, newCurrentTime)
        let previousEffectiveTime = effectivePlaybackTime()
        let previousShouldRender = shouldRenderDanmaku
        let previousIsPlaying = isPlaying
        let didChangeItems = newItemsRevision != lastItemsRevision
        let normalizedSettings = newSettings.normalized
        let didChangeRenderedSettings = abs(normalizedSettings.fontScale - settings.fontScale) > 0.001
            || abs(normalizedSettings.opacity - settings.opacity) > 0.001
            || normalizedSettings.displayArea != settings.displayArea
            || normalizedSettings.fontWeight != settings.fontWeight
        let didChangeTextMetrics = abs(normalizedSettings.fontScale - settings.fontScale) > 0.001
            || normalizedSettings.fontWeight != settings.fontWeight
        let didChangeInsets = abs(newTopInset - topInset) > 0.5 || abs(newBottomInset - bottomInset) > 0.5
        items = newItems
        if didChangeItems {
            rebuildTimeBuckets()
        }
        lastItemsRevision = newItemsRevision
        currentTime = sanitizedTime
        isPlaying = newIsPlaying
        playbackRate = normalizedRate
        isEnabled = newIsEnabled
        hasPresentedPlayback = newHasPresentedPlayback
        isLoadShedding = newIsLoadShedding
        settings = normalizedSettings
        topInset = max(0, newTopInset)
        bottomInset = max(0, newBottomInset)
        if didChangeTextMetrics {
            textSizeCache.removeAll(keepingCapacity: true)
            textSizeCacheOrder.removeAll(keepingCapacity: true)
        }

        let currentShouldRender = shouldRenderDanmaku
        if !currentShouldRender {
            cancelLayoutSettling()
            clearActiveLabels()
            setNextSpawnPosition(after: sanitizedTime)
            syncPlaybackAnchor(to: sanitizedTime)
            stopDisplayLink()
            updateAnimationPauseState()
            return
        }

        let jumped = abs(sanitizedTime - previousEffectiveTime) > seekJumpThreshold || sanitizedTime + 0.2 < previousEffectiveTime
        syncPlaybackAnchor(to: sanitizedTime)

        if isLayoutTransitioning, didChangeInsets {
            needsLayoutRebuildAfterTransition = true
            updateDisplayLinkState()
            updateAnimationPauseState()
            return
        }

        if !previousShouldRender || didChangeRenderedSettings || jumped {
            rebuildVisibleItems(at: sanitizedTime, animated: newIsPlaying)
            updateDisplayLinkState()
            updateAnimationPauseState()
            return
        }

        if didChangeInsets {
            rebuildVisibleItemsAfterLayoutChange(
                at: sanitizedTime,
                animated: newIsPlaying
            )
            updateDisplayLinkState()
            updateAnimationPauseState()
            return
        }

        if didChangeItems {
            if activeEntries.isEmpty {
                rebuildVisibleItems(at: sanitizedTime, animated: newIsPlaying)
            } else {
                setNextSpawnPosition(after: sanitizedTime)
            }
        }

        if previousIsPlaying != newIsPlaying && newIsPlaying {
            rebuildVisibleItems(at: sanitizedTime, animated: true)
        }

        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    func stop() {
        cancelLayoutSettling()
        stopDisplayLink()
        clearActiveLabels()
    }

    func synchronizePlaybackTime(_ playbackTime: TimeInterval, force: Bool = false) {
        let sanitizedTime = max(0, playbackTime)
        let previousEffectiveTime = effectivePlaybackTime()
        currentTime = sanitizedTime

        guard shouldRenderDanmaku else {
            setNextSpawnPosition(after: sanitizedTime)
            syncPlaybackAnchor(to: sanitizedTime)
            stopDisplayLink()
            updateAnimationPauseState()
            return
        }

        let drift = abs(sanitizedTime - previousEffectiveTime)
        let jumped = force || drift > seekJumpThreshold || sanitizedTime + 0.2 < previousEffectiveTime
        syncPlaybackAnchor(to: sanitizedTime)

        if jumped {
            rebuildVisibleItems(at: sanitizedTime, animated: isPlaying)
        }

        updateDisplayLinkState()
        updateAnimationPauseState()
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        guard shouldRenderDanmaku, isPlaying else { return }
        let playbackTime = effectivePlaybackTime(hostTime: displayLink.timestamp)
        retireExpiredActiveEntries(at: playbackTime)
        guard !isLayoutSettling, !isLayoutTransitioning else { return }
        spawnDueItems(at: playbackTime)
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        isUserInteractionEnabled = false
        layer.allowsGroupOpacity = false
    }

    private var shouldRenderDanmaku: Bool {
        isEnabled && hasPresentedPlayback && !items.isEmpty && bounds.width > 20 && bounds.height > 20
    }

    private var seekJumpThreshold: TimeInterval {
        max(1.25, 0.7 * playbackRate)
    }

    private func effectivePlaybackTime(hostTime: CFTimeInterval = CACurrentMediaTime()) -> TimeInterval {
        guard isPlaying else { return currentTime }
        let elapsed = max(0, hostTime - anchorHostTime)
        return max(0, anchorPlaybackTime + elapsed * playbackRate)
    }

    private func syncPlaybackAnchor(to playbackTime: TimeInterval) {
        anchorPlaybackTime = max(0, playbackTime)
        anchorHostTime = CACurrentMediaTime()
    }

    private func updateDisplayLinkState() {
        guard shouldRenderDanmaku, isPlaying, window != nil else {
            stopDisplayLink()
            return
        }
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.preferredFrameRateRange = preferredFrameRateRange
        displayLink?.isPaused = false
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateAnimationPauseState() {
        let shouldPause = !isPlaying || !shouldRenderDanmaku || window == nil
        let targetSpeed: Float = shouldPause ? 0 : Float(max(playbackRate, 0.1))
        guard abs(activeAnimationSpeed - targetSpeed) > 0.001 else { return }
        applyLayerAnimationSpeed(targetSpeed)
        activeAnimationSpeed = targetSpeed
    }

    private func applyLayerAnimationSpeed(_ targetSpeed: Float) {
        let now = CACurrentMediaTime()
        let currentLayerTime = layer.convertTime(now, from: nil)
        layer.speed = targetSpeed
        layer.timeOffset = 0
        layer.beginTime = 0
        if targetSpeed == 0 {
            layer.timeOffset = currentLayerTime
        } else {
            let convertedTime = layer.convertTime(now, from: nil)
            layer.beginTime = convertedTime - currentLayerTime
        }
    }

    private func beginLayoutSettling(animated: Bool) {
        layoutSettlingGeneration &+= 1
        let generation = layoutSettlingGeneration
        isLayoutSettling = true

        for (index, delay) in Self.layoutSettlingRebuildDelays.enumerated() {
            let completesSettling = index == Self.layoutSettlingRebuildDelays.indices.last
            if delay == 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.performLayoutSettledRebuild(
                        generation: generation,
                        animated: animated,
                        completesSettling: completesSettling
                    )
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(delay))) { [weak self] in
                    self?.performLayoutSettledRebuild(
                        generation: generation,
                        animated: animated,
                        completesSettling: completesSettling
                    )
                }
            }
        }
    }

    private func performLayoutSettledRebuild(
        generation: Int,
        animated: Bool,
        completesSettling: Bool
    ) {
        guard layoutSettlingGeneration == generation else { return }
        defer {
            if completesSettling, layoutSettlingGeneration == generation {
                isLayoutSettling = false
                updateDisplayLinkState()
                updateAnimationPauseState()
            }
        }
        guard shouldRenderDanmaku else {
            clearActiveLabels()
            return
        }
        rebuildVisibleItemsAfterLayoutChange(
            at: effectivePlaybackTime(),
            animated: completesSettling && animated && isPlaying
        )
    }

    private func cancelLayoutSettling() {
        layoutSettlingGeneration &+= 1
        isLayoutSettling = false
    }

    private func rebuildVisibleItems(at playbackTime: TimeInterval, animated: Bool) {
        isLayoutSettling = false
        advanceAnimationGeneration()
        clearActiveLabels()
        guard shouldRenderDanmaku else { return }
        scrollingLaneStates.removeAll(keepingCapacity: true)

        let replayStart = playbackTime - maximumDisplayDuration()
        let startIndex = firstItemIndex(atOrAfter: replayStart)
        let endIndex = firstItemIndex(after: playbackTime)
        guard startIndex < endIndex else {
            setNextSpawnPosition(after: playbackTime)
            return
        }

        var visibleItems: [DanmakuItem] = []
        visibleItems.reserveCapacity(min(maxActiveCount, endIndex - startIndex))
        for item in items[startIndex..<endIndex] {
            let age = playbackTime - item.time
            guard age >= 0, age < displayDuration(for: item) else { continue }
            visibleItems.append(item)
            if visibleItems.count > maxActiveCount {
                visibleItems.removeFirst(visibleItems.count - maxActiveCount)
            }
        }

        for item in visibleItems {
            spawn(item, at: playbackTime, animated: animated)
        }
        setNextSpawnPosition(after: playbackTime)
    }

    private func rebuildVisibleItemsAfterLayoutChange(
        at playbackTime: TimeInterval,
        animated: Bool
    ) {
        guard shouldRenderDanmaku else {
            clearActiveLabels()
            return
        }
        advanceAnimationGeneration()

        let existingEntries = activeEntries.values
        activeEntries.removeAll(keepingCapacity: true)
        scrollingLaneStates.removeAll(keepingCapacity: true)

        for entry in existingEntries {
            entry.completion?.cancel()
            guard entry.item.isSupported else {
                recycle(entry.label)
                continue
            }

            let duration = displayDuration(for: entry.item)
            let age = playbackTime - entry.item.time
            guard age >= 0 else {
                recycle(entry.label)
                continue
            }
            if !entry.item.isScrolling, age >= duration {
                recycle(entry.label)
                continue
            }
            if entry.item.isScrolling,
               shouldRetire(entry: entry, label: entry.label, at: playbackTime) {
                recycle(entry.label)
                continue
            }

            let fontSize = fontSize(for: entry.item)
            let font = UIFont.systemFont(ofSize: fontSize, weight: settings.fontWeight.uiFontWeight)
            let textSize = measuredTextSize(for: entry.item, font: font)
            let labelSize = CGSize(
                width: min(max(textSize.width + 18, 44), bounds.width * 1.45),
                height: max(textSize.height + 8, fontSize + 8)
            )
            configure(entry.label, for: entry.item, font: font, size: labelSize)

            let band = displayBand()
            let laneHeight = max(labelSize.height, fontSize + 10)
            let laneCount = max(1, Int(max(1, band.height) / laneHeight))
            let lane = entry.item.isScrolling
                ? stableLane(for: entry.item.id, laneCount: laneCount)
                : stableLane(for: entry.item.id, laneCount: laneCount)
            let y = yPosition(for: entry.item, lane: lane, laneHeight: laneHeight, band: band, labelSize: labelSize)
            entry.label.layer.removeAllAnimations()

            if entry.item.isScrolling {
                let travelDistance = scrollingTravelDistance(labelWidth: labelSize.width)
                let progress = min(max(age / duration, 0), 1)
                let timelineX = scrollingStartX(labelWidth: labelSize.width) - travelDistance * progress
                let startX = min(max(timelineX, -labelSize.width / 2), bounds.width + labelSize.width / 2)
                let endX = scrollingEndX(labelWidth: labelSize.width)
                let trajectory = scrollingTrajectory(
                    labelWidth: labelSize.width,
                    startX: startX,
                    endX: endX,
                    duration: duration
                )
                entry.label.center = CGPoint(x: startX, y: y)
                let animationDuration = animated
                    ? remainingScrollAnimationDuration(
                        fromX: startX,
                        toX: endX
                    )
                    : 0
                let entryAnimationGeneration = animationGeneration
                let completion = animated ? DanmakuAnimationCompletionDelegate { [weak self, weak label = entry.label] finished in
                    guard let self, let label else { return }
                    self.completeActiveLabelAnimation(
                        id: entry.id,
                        label: label,
                        animationGeneration: entryAnimationGeneration,
                        didFinishNaturally: finished
                    )
                } : nil
                activeEntries[entry.id] = ActiveEntry(
                    id: entry.id,
                    item: entry.item,
                    label: entry.label,
                    completion: completion,
                    createdAt: entry.createdAt,
                    animationGeneration: entryAnimationGeneration,
                    scrollingTrajectory: trajectory
                )
                if animated {
                    let animation = CABasicAnimation(keyPath: "position.x")
                    animation.fromValue = startX
                    animation.toValue = endX
                    animation.duration = animationDuration
                    animation.timingFunction = CAMediaTimingFunction(name: .linear)
                    animation.isRemovedOnCompletion = false
                    animation.fillMode = .forwards
                    animation.delegate = completion
                    entry.label.layer.add(animation, forKey: "danmaku.scroll")
                }
            } else {
                entry.label.center = CGPoint(x: bounds.midX, y: y)
                activeEntries[entry.id] = ActiveEntry(
                    id: entry.id,
                    item: entry.item,
                    label: entry.label,
                    completion: nil,
                    createdAt: entry.createdAt,
                    animationGeneration: animationGeneration,
                    scrollingTrajectory: nil
                )
            }
        }

        setNextSpawnPosition(after: playbackTime)
    }

    private func spawnDueItems(at playbackTime: TimeInterval) {
        skipExpiredItems(at: playbackTime)
        var spawnedCount = 0
        let spawnLimit = maxSpawnPerTick
        let currentBucket = timeBucketIndex(for: playbackTime)
        while nextBucketIndex < timeBuckets.count,
              timeBuckets[nextBucketIndex].index <= currentBucket,
              spawnedCount < spawnLimit {
            let bucket = timeBuckets[nextBucketIndex]
            if isBucketTooStale(bucket.index, at: playbackTime) {
                advanceToNextBucket()
                continue
            }

            let bucketItems = bucket.items
            while nextBucketItemIndex < bucketItems.count, spawnedCount < spawnLimit {
                let item = bucketItems[nextBucketItemIndex]
                nextBucketItemIndex += 1
                let age = playbackTime - item.time
                guard age >= -Self.timeBucketDuration, age < displayDuration(for: item) else { continue }
                spawn(item, at: playbackTime, animated: true)
                spawnedCount += 1
            }

            if nextBucketItemIndex >= bucketItems.count {
                advanceToNextBucket()
            }
        }
    }

    private func skipExpiredItems(at playbackTime: TimeInterval) {
        let maximumDuration = maximumDisplayDuration()
        while nextBucketIndex < timeBuckets.count {
            let bucket = timeBuckets[nextBucketIndex]
            guard bucketEndTime(for: bucket.index) >= playbackTime - maximumDuration else {
                advanceToNextBucket()
                continue
            }

            while nextBucketItemIndex < bucket.items.count,
                  playbackTime - bucket.items[nextBucketItemIndex].time > maximumDuration {
                nextBucketItemIndex += 1
            }
            if nextBucketItemIndex >= bucket.items.count {
                advanceToNextBucket()
                continue
            }
            return
        }
    }

    private func spawn(_ item: DanmakuItem, at playbackTime: TimeInterval, animated: Bool) {
        guard item.isSupported, bounds.width > 20, bounds.height > 20 else { return }
        guard canSpawnAdditionalItem else { return }

        let fontSize = fontSize(for: item)
        let font = UIFont.systemFont(ofSize: fontSize, weight: settings.fontWeight.uiFontWeight)
        let textSize = measuredTextSize(for: item, font: font)
        let labelSize = CGSize(
            width: min(max(textSize.width + 18, 44), bounds.width * 1.45),
            height: max(textSize.height + 8, fontSize + 8)
        )
        let label = dequeueLabel()
        configure(label, for: item, font: font, size: labelSize)

        let duration = displayDuration(for: item)
        let age = min(max(0, playbackTime - item.time), duration)
        let remainingPlaybackDuration = max(0.05, duration - age)
        let animationDuration = animated ? remainingPlaybackDuration : 0
        let band = displayBand()
        let laneHeight = max(labelSize.height, fontSize + 10)
        let laneCount = max(1, Int(max(1, band.height) / laneHeight))
        let lane: Int
        if item.isScrolling {
            guard let selectedLane = laneIndex(
                for: item,
                laneCount: laneCount,
                labelWidth: labelSize.width,
                at: item.time
            ) else {
                recycle(label)
                return
            }
            lane = selectedLane
        } else {
            lane = stableLane(for: item.id, laneCount: laneCount)
        }
        let y = yPosition(for: item, lane: lane, laneHeight: laneHeight, band: band, labelSize: labelSize)

        addSubview(label)
        let id = item.id
        let entryAnimationGeneration = animationGeneration
        let completion = animated ? DanmakuAnimationCompletionDelegate { [weak self, weak label] finished in
            guard let self, let label else { return }
            self.completeActiveLabelAnimation(
                id: id,
                label: label,
                animationGeneration: entryAnimationGeneration,
                didFinishNaturally: finished
            )
        } : nil
        activeEntries[id] = ActiveEntry(
            id: id,
            item: item,
            label: label,
            completion: completion,
            createdAt: CACurrentMediaTime(),
            animationGeneration: entryAnimationGeneration,
            scrollingTrajectory: item.isScrolling
                ? scrollingTrajectory(
                    labelWidth: labelSize.width,
                    startX: scrollingStartX(labelWidth: labelSize.width)
                        - scrollingTravelDistance(labelWidth: labelSize.width)
                        * min(max(age / duration, 0), 1),
                    endX: scrollingEndX(labelWidth: labelSize.width),
                    duration: duration
                )
                : nil
        )

        if item.isScrolling {
            let travelDistance = scrollingTravelDistance(labelWidth: labelSize.width)
            let progress = min(max(age / duration, 0), 1)
            let startX = scrollingStartX(labelWidth: labelSize.width) - travelDistance * progress
            let endX = scrollingEndX(labelWidth: labelSize.width)
            label.center = CGPoint(x: startX, y: y)
            if animated {
                let animation = CABasicAnimation(keyPath: "position.x")
                animation.fromValue = startX
                animation.toValue = endX
                animation.duration = remainingScrollAnimationDuration(
                    fromX: startX,
                    toX: endX
                )
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                animation.isRemovedOnCompletion = false
                animation.fillMode = .forwards
                animation.delegate = completion
                label.layer.add(animation, forKey: "danmaku.scroll")
            }
        } else {
            label.center = CGPoint(x: bounds.midX, y: y)
            if animated {
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = [0, 1, 1, 0]
                animation.keyTimes = [0, 0.06, 0.92, 1]
                animation.duration = animationDuration
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.isRemovedOnCompletion = true
                animation.delegate = completion
                label.layer.opacity = 0
                label.layer.add(animation, forKey: "danmaku.opacity")
            }
        }
    }

    private func configure(_ label: UILabel, for item: DanmakuItem, font: UIFont, size: CGSize) {
        label.text = item.text
        label.font = font
        label.textAlignment = .center
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        label.textColor = UIColor.danmakuRGB(item.color).withAlphaComponent(settings.opacity)
        label.alpha = 1
        label.layer.opacity = 1
        label.frame = CGRect(origin: .zero, size: size)
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.92
        label.layer.shadowRadius = 1.4
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        label.layer.shouldRasterize = true
        label.layer.rasterizationScale = window?.screen.scale ?? traitCollection.displayScale
        label.layer.allowsEdgeAntialiasing = true
    }

    private func dequeueLabel() -> UILabel {
        if let label = reusableLabels.popLast() {
            label.layer.removeAllAnimations()
            return label
        }
        let label = UILabel()
        label.backgroundColor = .clear
        label.isOpaque = false
        return label
    }

    private func recycle(_ label: UILabel) {
        label.text = nil
        label.layer.removeAllAnimations()
        label.removeFromSuperview()
        guard reusableLabels.count < 72 else { return }
        reusableLabels.append(label)
    }

    private func clearActiveLabels() {
        let entries = activeEntries.values
        activeEntries.removeAll(keepingCapacity: true)
        for entry in entries {
            entry.completion?.cancel()
            entry.label.layer.removeAllAnimations()
            recycle(entry.label)
        }
    }

    private func removeActiveLabel(id: String, label: UILabel, shouldRecycle: Bool) {
        guard let entry = activeEntries[id], entry.label === label else { return }
        entry.completion?.cancel()
        activeEntries[id] = nil
        label.layer.removeAllAnimations()
        if shouldRecycle {
            recycle(label)
        } else {
            label.removeFromSuperview()
        }
    }

    private func completeActiveLabelAnimation(
        id: String,
        label: UILabel,
        animationGeneration: Int,
        didFinishNaturally: Bool
    ) {
        guard let entry = activeEntries[id], entry.label === label else { return }
        guard entry.animationGeneration == animationGeneration,
              self.animationGeneration == animationGeneration
        else { return }
        if entry.item.isScrolling, isLayoutSettling {
            return
        }
        if entry.item.isScrolling, !didFinishNaturally {
            return
        }
        let playbackTime = effectivePlaybackTime()
        if shouldRetire(
            entry: entry,
            label: label,
            at: playbackTime,
            allowsTimelineFallback: didFinishNaturally
        ) {
            removeActiveLabel(id: id, label: label, shouldRecycle: true)
            return
        }

        guard entry.item.isScrolling, shouldRenderDanmaku else { return }
        rebuildVisibleItemsAfterLayoutChange(at: playbackTime, animated: isPlaying)
    }

    private func advanceAnimationGeneration() {
        animationGeneration &+= 1
    }

    private func retireExpiredActiveEntries(at playbackTime: TimeInterval) {
        guard !activeEntries.isEmpty else { return }
        for entry in Array(activeEntries.values)
        where shouldRetire(entry: entry, label: entry.label, at: playbackTime) {
            removeActiveLabel(id: entry.id, label: entry.label, shouldRecycle: true)
        }
    }

    private func shouldRetire(
        entry: ActiveEntry,
        label: UILabel,
        at playbackTime: TimeInterval,
        allowsTimelineFallback: Bool = false
    ) -> Bool {
        let duration = entry.scrollingTrajectory?.displayDuration ?? displayDuration(for: entry.item)
        let age = playbackTime - entry.item.time
        guard age >= 0 else { return false }
        guard entry.item.isScrolling else { return age >= duration - 0.04 }
        guard !isLayoutSettling else {
            return allowsTimelineFallback && age >= duration + 0.35
        }

        let currentX = label.layer.presentation()?.position.x ?? label.center.x
        let endX = entry.scrollingTrajectory?.endX ?? scrollingEndX(labelWidth: label.bounds.width)
        if currentX <= endX + 1 {
            return true
        }

        return allowsTimelineFallback && age >= duration + 0.18
    }

    private func scrollingStartX(labelWidth: CGFloat) -> CGFloat {
        bounds.width + labelWidth / 2
    }

    private func scrollingEndX(labelWidth: CGFloat) -> CGFloat {
        -labelWidth / 2 - scrollingRetirementOverscan
    }

    private func scrollingTravelDistance(labelWidth: CGFloat) -> CGFloat {
        max(scrollingStartX(labelWidth: labelWidth) - scrollingEndX(labelWidth: labelWidth), 1)
    }

    private func scrollingTrajectory(
        labelWidth: CGFloat,
        startX: CGFloat,
        endX: CGFloat,
        duration: TimeInterval
    ) -> ScrollingTrajectory {
        ScrollingTrajectory(
            labelWidth: labelWidth,
            surfaceWidth: bounds.width,
            startX: startX,
            endX: endX,
            displayDuration: duration
        )
    }

    private func remainingScrollAnimationDuration(
        fromX startX: CGFloat,
        toX endX: CGFloat
    ) -> TimeInterval {
        let remainingDistance = max(startX - endX, 1)
        return max(0.05, TimeInterval(remainingDistance / scrollingPixelsPerSecond))
    }

    private var scrollingRetirementOverscan: CGFloat {
        min(max(bounds.width * 0.035, 8), 28)
    }

    private var canSpawnAdditionalItem: Bool {
        activeEntries.count < maxActiveCount
    }

    private func measuredTextSize(for item: DanmakuItem, font: UIFont) -> CGSize {
        let key = TextMeasurementKey(
            text: item.text,
            fontSizeTenths: Int((font.pointSize * 10).rounded()),
            fontWeight: settings.fontWeight
        )
        if let cached = textSizeCache[key] {
            return cached
        }

        let size = (item.text as NSString).size(withAttributes: [.font: font])
        let measured = CGSize(width: ceil(size.width), height: ceil(max(size.height, font.lineHeight)))
        textSizeCache[key] = measured
        textSizeCacheOrder.append(key)
        trimTextSizeCacheIfNeeded()
        return measured
    }

    private func trimTextSizeCacheIfNeeded() {
        guard textSizeCacheOrder.count > 520 else { return }
        let overflow = textSizeCacheOrder.count - 420
        let removedKeys = textSizeCacheOrder.prefix(overflow)
        removedKeys.forEach { textSizeCache[$0] = nil }
        textSizeCacheOrder.removeFirst(overflow)
    }

    private func displayBand() -> CGRect {
        let usableMinY = max(0, topInset)
        let usableMaxY = max(usableMinY + 1, bounds.height - max(0, bottomInset))
        let usableHeight = max(1, usableMaxY - usableMinY)
        let fraction: CGFloat
        switch settings.displayArea {
        case .topQuarter:
            fraction = 0.25
        case .topHalf:
            fraction = 0.5
        case .topThreeQuarters:
            fraction = 0.75
        case .center:
            fraction = 0.5
        case .full:
            fraction = 1
        }
        let targetHeight = bounds.height * fraction
        let minimumHeight = minimumDisplayBandHeight(for: fraction, usableHeight: usableHeight)
        let height = min(usableHeight, max(targetHeight, minimumHeight))
        return CGRect(x: 0, y: usableMinY, width: bounds.width, height: height)
    }

    private func minimumDisplayBandHeight(for fraction: CGFloat, usableHeight: CGFloat) -> CGFloat {
        guard fraction < 1 else { return usableHeight }
        let compactScale = bounds.width > 640 ? 0.86 : 0.70
        let representativeFontSize = min(
            max(25 * compactScale * CGFloat(settings.fontScale), bounds.width > 640 ? 13.5 : 11.7),
            (bounds.width > 640 ? 24 : 18) * 1.35
        )
        let laneHeight = representativeFontSize + 10
        let preferredLaneCount: CGFloat
        if bounds.height < 220 {
            preferredLaneCount = fraction <= 0.25 ? 3 : 4
        } else {
            preferredLaneCount = fraction <= 0.25 ? 4 : 5
        }
        return min(usableHeight, laneHeight * preferredLaneCount)
    }

    private func yPosition(
        for item: DanmakuItem,
        lane: Int,
        laneHeight: CGFloat,
        band: CGRect,
        labelSize: CGSize
    ) -> CGFloat {
        if item.isBottomAnchored {
            let anchoredLaneCount = min(3, max(1, Int(max(1, band.height) / laneHeight)))
            let anchoredLane = stableLane(for: item.id, laneCount: anchoredLaneCount)
            let y = band.maxY - laneHeight * (CGFloat(anchoredLane) + 0.5)
            return min(max(y, labelSize.height / 2), bounds.height - labelSize.height / 2)
        }
        if item.isTopAnchored {
            let anchoredLaneCount = min(3, max(1, Int(max(1, band.height) / laneHeight)))
            let anchoredLane = stableLane(for: item.id, laneCount: anchoredLaneCount)
            let y = band.minY + laneHeight * (CGFloat(anchoredLane) + 0.5)
            return min(max(y, labelSize.height / 2), bounds.height - labelSize.height / 2)
        }
        let y = band.minY + laneHeight * (CGFloat(lane) + 0.5)
        return min(max(y, labelSize.height / 2), bounds.height - labelSize.height / 2)
    }

    private func laneIndex(
        for item: DanmakuItem,
        laneCount: Int,
        labelWidth: CGFloat,
        at itemTime: TimeInterval
    ) -> Int? {
        guard laneCount > 1, item.isScrolling else { return 0 }
        let startLane = stableLane(for: item.id, laneCount: laneCount)
        for offset in 0..<laneCount {
            let lane = (startLane + offset) % laneCount
            if (scrollingLaneStates[lane]?.releaseTime ?? 0) <= itemTime {
                scrollingLaneStates[lane] = LaneState(
                    releaseTime: itemTime + laneEntranceDelay(for: labelWidth),
                    itemWidth: labelWidth
                )
                return lane
            }
        }

        guard let earliest = scrollingLaneStates.min(by: { lhs, rhs in
            lhs.value.releaseTime < rhs.value.releaseTime
        }) else {
            return startLane
        }
        guard earliest.value.releaseTime - itemTime <= maxLaneOverlapTolerance else {
            return nil
        }
        scrollingLaneStates[earliest.key] = LaneState(
            releaseTime: itemTime + laneEntranceDelay(for: labelWidth),
            itemWidth: labelWidth
        )
        return earliest.key
    }

    private func laneEntranceDelay(for labelWidth: CGFloat) -> TimeInterval {
        let gap = bounds.width > 640 ? 40.0 : 30.0
        let travelDistance = max(bounds.width + labelWidth, 1)
        let protectedWidth = min(labelWidth + gap, bounds.width * 0.72)
        return scrollDuration * TimeInterval(protectedWidth / travelDistance)
    }

    private var maxLaneOverlapTolerance: TimeInterval {
        bounds.width > 640 ? 0.16 : 0.10
    }

    private func displayDuration(for item: DanmakuItem) -> TimeInterval {
        item.isScrolling ? scrollDuration : 4.2
    }

    private func maximumDisplayDuration() -> TimeInterval {
        max(scrollDuration, 4.2)
    }

    private var scrollDuration: TimeInterval {
        bounds.width > 640 ? 8.4 : 7.2
    }

    private var scrollingPixelsPerSecond: CGFloat {
        let representativeLabelWidth = min(max(bounds.width * 0.36, 160), bounds.width * 0.85)
        return scrollingTravelDistance(labelWidth: representativeLabelWidth) / max(scrollDuration, 0.1)
    }

    private var maxActiveCount: Int {
        let baseCount = bounds.width > 640 ? 44 : 24
        return max(isLoadShedding ? 5 : 8, Int(Double(baseCount) * adaptiveDanmakuLoadFactor))
    }

    private var maxSpawnPerTick: Int {
        let baseCount = bounds.width > 640 ? 6 : 4
        return max(1, Int(Double(baseCount) * adaptiveDanmakuLoadFactor))
    }

    private var adaptiveDanmakuLoadFactor: Double {
        let environment = PlaybackEnvironment.current
        let loadSheddingFactor = isLoadShedding ? 0.46 : 1.0
        let rateFactor: Double
        if playbackRate >= 1.75 {
            rateFactor = 0.58
        } else if playbackRate > 1.15 {
            rateFactor = 0.72
        } else {
            rateFactor = 1.0
        }
        if environment.isThermallyConstrained || environment.isLowPowerModeEnabled {
            return min(settings.loadFactor, 0.50) * loadSheddingFactor * rateFactor
        }
        if environment.isThermallyElevated {
            return min(settings.loadFactor, 0.66) * loadSheddingFactor * rateFactor
        }
        if environment.shouldPreferConservativePlayback {
            return min(settings.loadFactor, 0.72) * loadSheddingFactor * rateFactor
        }
        return settings.loadFactor * loadSheddingFactor * rateFactor
    }

    private var preferredFrameRateRange: CAFrameRateRange {
        let environment = PlaybackEnvironment.current
        if isLoadShedding || playbackRate >= 1.75 || environment.isThermallyConstrained {
            return CAFrameRateRange(minimum: 10, maximum: 18, preferred: 14)
        }
        if playbackRate > 1.15 || environment.isThermallyElevated || environment.isLowPowerModeEnabled {
            return CAFrameRateRange(minimum: 10, maximum: 20, preferred: 16)
        }
        return CAFrameRateRange(minimum: 12, maximum: 24, preferred: 20)
    }

    private static let layoutSettlingRebuildDelays: [UInt64] = [
        0,
        120_000_000,
        280_000_000
    ]

    private static let timeBucketDuration: TimeInterval = 0.1

    private func fontSize(for item: DanmakuItem) -> CGFloat {
        let compactScale = bounds.width > 640 ? 0.86 : 0.70
        let maximumSize: CGFloat = bounds.width > 640 ? 24 : 18
        let minimumSize: CGFloat = bounds.width > 640 ? 15 : 13
        let scaledSize = CGFloat(item.fontSize) * compactScale * CGFloat(settings.fontScale)
        return min(max(scaledSize, minimumSize * 0.9), maximumSize * 1.35)
    }

    private func rebuildTimeBuckets() {
        timeBuckets.removeAll(keepingCapacity: true)
        timeBuckets.reserveCapacity(min(items.count, 600))
        for item in items {
            let bucketIndex = timeBucketIndex(for: item.time)
            if let lastIndex = timeBuckets.indices.last,
               timeBuckets[lastIndex].index == bucketIndex {
                timeBuckets[lastIndex].items.append(item)
            } else {
                timeBuckets.append(TimeBucket(index: bucketIndex, items: [item]))
            }
        }
        nextBucketIndex = 0
        nextBucketItemIndex = 0
    }

    private func setNextSpawnPosition(after playbackTime: TimeInterval) {
        guard !timeBuckets.isEmpty else {
            nextBucketIndex = 0
            nextBucketItemIndex = 0
            return
        }

        let nextItemIndex = firstItemIndex(after: playbackTime)
        guard nextItemIndex < items.count else {
            nextBucketIndex = timeBuckets.count
            nextBucketItemIndex = 0
            return
        }

        let bucketIndex = timeBucketIndex(for: items[nextItemIndex].time)
        nextBucketIndex = firstTimeBucketIndex(atOrAfter: bucketIndex)
        guard nextBucketIndex < timeBuckets.count else {
            nextBucketItemIndex = 0
            return
        }

        let bucketItems = timeBuckets[nextBucketIndex].items
        nextBucketItemIndex = bucketItems.firstIndex { $0.time > playbackTime } ?? bucketItems.count
        if nextBucketItemIndex >= bucketItems.count {
            advanceToNextBucket()
        }
    }

    private func advanceToNextBucket() {
        nextBucketIndex += 1
        nextBucketItemIndex = 0
    }

    private func isBucketTooStale(_ bucketIndex: Int, at playbackTime: TimeInterval) -> Bool {
        playbackTime - bucketEndTime(for: bucketIndex) > maximumBucketSpawnDelay
    }

    private var maximumBucketSpawnDelay: TimeInterval {
        if isLoadShedding {
            return 0.22
        }
        if playbackRate > 1.15 || PlaybackEnvironment.current.isThermallyElevated {
            return 0.32
        }
        return 0.48
    }

    private func timeBucketIndex(for time: TimeInterval) -> Int {
        Int((max(0, time) / Self.timeBucketDuration).rounded(.down))
    }

    private func bucketEndTime(for bucketIndex: Int) -> TimeInterval {
        TimeInterval(bucketIndex + 1) * Self.timeBucketDuration
    }

    private func firstTimeBucketIndex(atOrAfter bucketIndex: Int) -> Int {
        var lower = 0
        var upper = timeBuckets.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if timeBuckets[middle].index < bucketIndex {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func firstItemIndex(atOrAfter time: TimeInterval) -> Int {
        var lower = 0
        var upper = items.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if items[middle].time < time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func firstItemIndex(after time: TimeInterval) -> Int {
        var lower = 0
        var upper = items.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if items[middle].time <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func stableLane(for id: String, laneCount: Int) -> Int {
        guard laneCount > 1 else { return 0 }
        var hash: UInt64 = 5_381
        for scalar in id.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return Int(hash % UInt64(laneCount))
    }

}

private final class DanmakuAnimationCompletionDelegate: NSObject, CAAnimationDelegate {
    private let completion: (Bool) -> Void
    private var isCancelled = false

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard !isCancelled else { return }
        completion(flag)
    }

    func cancel() {
        isCancelled = true
    }
}

private extension UIColor {
    static func danmakuRGB(_ rgb: UInt32) -> UIColor {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

private extension DanmakuFontWeightOption {
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .light:
            return .light
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        case .heavy:
            return .heavy
        case .black:
            return .black
        }
    }
}
