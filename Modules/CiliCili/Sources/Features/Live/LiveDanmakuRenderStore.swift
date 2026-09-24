import Combine
import Foundation
import SwiftUI

@MainActor
final class LiveDanmakuRenderStore: ObservableObject {
    @Published private(set) var items: [DanmakuItem] = []
    @Published private(set) var itemsRevision = 0
    @Published private(set) var chatItems: [DanmakuItem] = []
    @Published private(set) var chatItemsRevision = 0
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var isEnabled: Bool
    @Published private(set) var settings: DanmakuSettings
    @Published private(set) var connectionPhase: LiveDanmakuDiagnosticPhase = .idle
    @Published private(set) var connectionError: String?
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var historyError: String?
    let diagnosticsStore: LiveDanmakuDiagnosticsStore
    private var pendingLiveItems = [DanmakuItem]()
    private var pendingLiveItemsRetainingLimit = 240
    private var pendingLiveItemsFlushTask: Task<Void, Never>?
    private var defersRenderedUpdates = false
    private var deferredPlaybackTime: TimeInterval?
    private var deferredHistoryItems = [DanmakuItem]()
    private var deferredHistoryItemsRetainingLimit = 240

    init(
        isEnabled: Bool,
        settings: DanmakuSettings,
        diagnostics: LiveDanmakuDiagnosticSnapshot
    ) {
        self.isEnabled = isEnabled
        self.settings = settings.normalized
        self.diagnosticsStore = LiveDanmakuDiagnosticsStore(snapshot: diagnostics)
    }

    deinit {
        pendingLiveItemsFlushTask?.cancel()
    }

    var itemCount: Int {
        items.count
    }

    func updateEnabled(_ isEnabled: Bool) {
        guard self.isEnabled != isEnabled else { return }
        self.isEnabled = isEnabled
    }

    func updateSettings(_ settings: DanmakuSettings) {
        let normalized = settings.normalized
        guard self.settings != normalized else { return }
        self.settings = normalized
    }

    func updateConnectionState(
        phase: LiveDanmakuDiagnosticPhase,
        error: String?
    ) {
        guard connectionPhase != phase || connectionError != error else { return }
        connectionPhase = phase
        connectionError = error
    }

    func updateHistoryLoading(_ isLoading: Bool) {
        if isLoading {
            historyError = nil
        }
        guard isLoadingHistory != isLoading else { return }
        isLoadingHistory = isLoading
    }

    func recordHistoryFailure(_ error: String) {
        isLoadingHistory = false
        historyError = error
    }

    func resetHistoryState() {
        isLoadingHistory = false
        historyError = nil
    }

    func updatePlaybackTime(_ playbackTime: TimeInterval) {
        let sanitizedTime = max(0, playbackTime)
        guard !defersRenderedUpdates else {
            deferredPlaybackTime = sanitizedTime
            return
        }
        guard abs(self.playbackTime - sanitizedTime) >= 0.1 || sanitizedTime == 0 else { return }
        self.playbackTime = sanitizedTime
    }

    /// Holds high-frequency renderer publications while a system rotation owns
    /// the main thread. Incoming messages remain queued and are flushed once.
    func setRenderedUpdatesDeferred(_ deferred: Bool) {
        guard defersRenderedUpdates != deferred else { return }
        defersRenderedUpdates = deferred
        guard !deferred else { return }

        if let deferredPlaybackTime {
            self.deferredPlaybackTime = nil
            updatePlaybackTime(deferredPlaybackTime)
        }
        flushPendingLiveItems()
        flushDeferredHistoryItems()
    }

    func appendItems(_ newItems: [DanmakuItem], retainingLimit limit: Int) {
        guard !newItems.isEmpty else { return }
        pendingLiveItems.append(contentsOf: newItems)
        pendingLiveItemsRetainingLimit = limit
        schedulePendingLiveItemsFlush(retainingLimit: limit)
    }

    func flushPendingLiveItems() {
        pendingLiveItemsFlushTask?.cancel()
        pendingLiveItemsFlushTask = nil
        guard !defersRenderedUpdates else { return }
        guard !pendingLiveItems.isEmpty else { return }
        let itemsToAppend = pendingLiveItems
        pendingLiveItems.removeAll(keepingCapacity: true)
        appendLiveItems(itemsToAppend, retainingLimit: pendingLiveItemsRetainingLimit)
    }

    private func schedulePendingLiveItemsFlush(retainingLimit limit: Int) {
        guard pendingLiveItemsFlushTask == nil else { return }
        pendingLiveItemsFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: LivePlaybackPolicy.danmakuRenderBatchWindowNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.pendingLiveItemsFlushTask = nil
            guard !self.pendingLiveItems.isEmpty else { return }
            let itemsToAppend = self.pendingLiveItems
            self.pendingLiveItems.removeAll(keepingCapacity: true)
            self.appendLiveItems(itemsToAppend, retainingLimit: limit)
        }
    }

    private func appendLiveItems(_ newItems: [DanmakuItem], retainingLimit limit: Int) {
        items.append(contentsOf: newItems)
        if items.count > limit {
            items.removeFirst(items.count - limit)
        }
        itemsRevision &+= 1

        chatItems.append(contentsOf: newItems)
        if chatItems.count > limit {
            chatItems.removeFirst(chatItems.count - limit)
        }
        chatItemsRevision &+= 1
    }

    func prependHistoryItems(_ newItems: [DanmakuItem], retainingLimit limit: Int) {
        guard !newItems.isEmpty else { return }
        guard !defersRenderedUpdates else {
            deferredHistoryItems.append(contentsOf: newItems)
            deferredHistoryItemsRetainingLimit = limit
            return
        }
        appendHistoryItems(newItems, retainingLimit: limit)
    }

    private func appendHistoryItems(_ newItems: [DanmakuItem], retainingLimit limit: Int) {
        let existingIDs = Set(chatItems.map(\.id))
        let uniqueItems = newItems.filter { !existingIDs.contains($0.id) }
        guard !uniqueItems.isEmpty else { return }
        chatItems.insert(contentsOf: uniqueItems, at: 0)
        if chatItems.count > limit {
            chatItems.removeLast(chatItems.count - limit)
        }
        chatItemsRevision &+= 1
    }

    private func flushDeferredHistoryItems() {
        guard !defersRenderedUpdates, !deferredHistoryItems.isEmpty else { return }
        let itemsToPrepend = deferredHistoryItems
        deferredHistoryItems.removeAll(keepingCapacity: true)
        appendHistoryItems(itemsToPrepend, retainingLimit: deferredHistoryItemsRetainingLimit)
    }

    func clearItems() {
        pendingLiveItemsFlushTask?.cancel()
        pendingLiveItemsFlushTask = nil
        pendingLiveItems.removeAll(keepingCapacity: true)
        deferredPlaybackTime = nil
        deferredHistoryItems.removeAll(keepingCapacity: true)
        if !items.isEmpty {
            items.removeAll()
            itemsRevision &+= 1
        }
        if !chatItems.isEmpty {
            chatItems.removeAll()
            chatItemsRevision &+= 1
        }
    }

    func updateDiagnostics(_ diagnostics: LiveDanmakuDiagnosticSnapshot) {
        diagnosticsStore.update(diagnostics)
    }
}

@MainActor
final class LiveDanmakuDiagnosticsStore: ObservableObject {
    @Published private(set) var snapshot: LiveDanmakuDiagnosticSnapshot

    init(snapshot: LiveDanmakuDiagnosticSnapshot) {
        self.snapshot = snapshot
    }

    func update(_ snapshot: LiveDanmakuDiagnosticSnapshot) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }
}
