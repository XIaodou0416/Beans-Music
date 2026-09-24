import Foundation

extension LiveRoomViewModel {
    func showLiveDanmakuSettings() {
        isShowingLiveDanmakuSettings = true
    }

    func toggleDanmaku() {
        isDanmakuEnabled.toggle()
        libraryStore.setDanmakuEnabled(isDanmakuEnabled)
        refreshLiveDanmakuDiagnosticsRenderState()
        if isDanmakuEnabled {
            resumeLiveDanmakuIfNeeded()
        } else {
            stopLiveDanmaku(clearItems: true)
        }
    }

    func updateDanmakuSettings(_ settings: DanmakuSettings) {
        let normalizedSettings = settings.normalized
        guard danmakuSettings != normalizedSettings else { return }
        libraryStore.setDanmakuSettings(normalizedSettings)
    }

    func toggleLiveDanmakuDiagnostics() {
        isLiveDanmakuDiagnosticsEnabled.toggle()
        refreshLiveDanmakuDiagnosticsRenderState(forcePublish: true)
        if isLiveDanmakuDiagnosticsEnabled {
            resumeLiveDanmakuIfNeeded()
        }
    }

    func setDanmakuHidesInPortrait(_ hidesInPortrait: Bool) {
        guard danmakuSettings.hidesInPortrait != hidesInPortrait else { return }
        var settings = danmakuSettings
        settings.hidesInPortrait = hidesInPortrait
        libraryStore.setDanmakuSettings(settings)
    }

    func suspendLiveDanmaku() {
        stopLiveDanmaku(clearItems: false)
    }

    func resumeLiveDanmakuIfNeeded() {
        guard isDanmakuEnabled, playerViewModel != nil, roomID > 0 else { return }
        startLiveDanmakuIfNeeded(roomID: roomID)
    }

    func applyGlobalDanmakuEnabled(_ isEnabled: Bool) {
        guard isDanmakuEnabled != isEnabled else { return }
        isDanmakuEnabled = isEnabled
        liveDanmakuRenderStore.updateEnabled(isEnabled)
        refreshLiveDanmakuDiagnosticsRenderState()
        if isEnabled {
            resumeLiveDanmakuIfNeeded()
        } else {
            stopLiveDanmaku(clearItems: true)
        }
    }

    func startLiveDanmakuIfNeeded(roomID: Int) {
        guard isDanmakuEnabled, liveDanmakuService == nil else { return }
        liveDanmakuRenderStore.updateConnectionState(phase: .fetchingConfig, error: nil)
        prefetchLiveDanmakuHistoryIfNeeded(roomID: roomID)
        liveDanmakuStartDate = Date()
        liveDanmakuRenderStore.updatePlaybackTime(0)
        let service = LiveDanmakuService(
            roomID: roomID,
            api: api,
            onDiagnostics: { [weak self] event in
                self?.handleLiveDanmakuDiagnosticEvent(event)
            },
            onItems: { [weak self] items in
                self?.appendLiveDanmakuItems(items)
            }
        )
        liveDanmakuService = service
        service.start()
        startLiveDanmakuClock()
    }

    func scheduleLiveDanmakuStart(
        roomID: Int,
        playerViewModel: PlayerStateViewModel,
        candidate: LiveStreamURLCandidate,
        generation: Int
    ) {
        guard isDanmakuEnabled else { return }
        let defersForTransportStream = LiveStartupAuxiliaryPolicy.defersUntilFirstFrame(
            streamFormat: candidate.formatName
        )
        if defersForTransportStream {
            let existingFirstFrameHandler = playerViewModel.onFirstFramePresented
            playerViewModel.onFirstFramePresented = { [weak self, weak playerViewModel] in
                existingFirstFrameHandler?()
                guard let self,
                      let playerViewModel,
                      self.isCurrentLoad(generation),
                      self.playerViewModel === playerViewModel
                else { return }
                self.startLiveDanmakuIfNeeded(roomID: roomID)
            }
            PlayerMetricsLog.record(
                .network,
                metricsID: "live-\(roomID)",
                title: title,
                message: "liveDanmakuStartup=deferredTSUntilFirstFrame"
            )
            if playerViewModel.hasPresentedPlayback {
                startLiveDanmakuIfNeeded(roomID: roomID)
            }
            return
        }
        PlayerMetricsLog.record(
            .network,
            metricsID: "live-\(roomID)",
            title: title,
            message: "liveDanmakuStartup=parallelBeforeFirstFrame"
        )
        guard isCurrentLoad(generation), self.playerViewModel === playerViewModel else { return }
        startLiveDanmakuIfNeeded(roomID: roomID)
    }

    func stopLiveDanmaku(clearItems: Bool) {
        liveDanmakuRenderStore.flushPendingLiveItems()
        liveDanmakuService?.stop()
        liveDanmakuService = nil
        liveDanmakuClockTask?.cancel()
        liveDanmakuClockTask = nil
        liveDanmakuHistoryTask?.cancel()
        liveDanmakuHistoryTask = nil
        liveDanmakuStartDate = nil
        liveDanmakuRenderStore.updatePlaybackTime(0)
        liveDanmakuRenderStore.updateConnectionState(phase: .stopped, error: nil)
        liveDanmakuRenderStore.resetHistoryState()
        if clearItems {
            liveDanmakuHistoryLoadedRoomID = nil
            liveDanmakuRenderStore.clearItems()
        }
        refreshLiveDanmakuDiagnosticsRenderState()
    }

    func startLiveDanmakuClock() {
        liveDanmakuClockTask?.cancel()
        liveDanmakuClockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let liveDanmakuStartDate = self.liveDanmakuStartDate else { return }
                    self.liveDanmakuRenderStore.updatePlaybackTime(
                        max(0, Date().timeIntervalSince(liveDanmakuStartDate))
                    )
                }
            }
        }
    }

    func appendLiveDanmakuItems(_ items: [DanmakuItem]) {
        guard isDanmakuEnabled, !items.isEmpty else { return }
        liveDanmakuRenderStore.appendItems(items, retainingLimit: 240)
        if let liveDanmakuStartDate {
            liveDanmakuRenderStore.updatePlaybackTime(max(0, Date().timeIntervalSince(liveDanmakuStartDate)))
        }
        refreshLiveDanmakuDiagnosticsRenderState()
    }

    func prefetchLiveDanmakuHistoryIfNeeded(roomID: Int) {
        guard liveDanmakuHistoryLoadedRoomID != roomID, liveDanmakuHistoryTask == nil else { return }
        liveDanmakuRenderStore.updateHistoryLoading(true)
        let api = self.api
        liveDanmakuHistoryTask = Task { [weak self, api] in
            do {
                let result = try await api.fetchLiveDanmakuHistory(roomID: roomID)
                guard !Task.isCancelled, let self else { return }
                self.liveDanmakuHistoryTask = nil
                self.liveDanmakuRenderStore.updateHistoryLoading(false)
                self.appendLiveDanmakuHistory(result, roomID: roomID)
                self.liveDanmakuHistoryLoadedRoomID = roomID
                self.liveDanmakuDiagnosticsDraft.apply(.historyLoaded(count: result.count))
                self.refreshLiveDanmakuDiagnosticsRenderState()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.liveDanmakuHistoryTask = nil
                self.liveDanmakuRenderStore.recordHistoryFailure(error.localizedDescription)
                self.liveDanmakuDiagnosticsDraft.apply(
                    .historyFailed(error: error.localizedDescription)
                )
                self.refreshLiveDanmakuDiagnosticsRenderState()
            }
        }
    }

    func appendLiveDanmakuHistory(
        _ messages: [LiveDanmakuHistoryMessage],
        roomID: Int
    ) {
        guard isDanmakuEnabled else { return }
        let items = messages.enumerated().compactMap { index, message -> DanmakuItem? in
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let senderName = message.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
            let timeline = message.timeline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            return DanmakuItem(
                id: "live-history-\(roomID)-\(index)-\(timeline)",
                time: 0,
                mode: 1,
                fontSize: 24,
                color: 0xE5E7EB,
                text: text,
                senderName: senderName?.isEmpty == false ? senderName : nil
            )
        }
        liveDanmakuRenderStore.prependHistoryItems(items, retainingLimit: 240)
    }

    func handleLiveDanmakuDiagnosticEvent(_ event: LiveDanmakuDiagnosticEvent) {
        liveDanmakuDiagnosticsDraft.apply(event)
        liveDanmakuRenderStore.updateConnectionState(
            phase: liveDanmakuDiagnosticsDraft.phase,
            error: liveDanmakuDiagnosticsDraft.lastError
        )
        applyCurrentRenderStateToDiagnosticsDraft()
        publishLiveDanmakuDiagnosticsIfNeeded()
    }

    func refreshLiveDanmakuDiagnosticsRenderState(forcePublish: Bool = false) {
        applyCurrentRenderStateToDiagnosticsDraft()
        publishLiveDanmakuDiagnosticsIfNeeded(force: forcePublish)
    }

    func applyCurrentRenderStateToDiagnosticsDraft() {
        liveDanmakuDiagnosticsDraft.apply(
            .renderState(
                isDanmakuEnabled: isDanmakuEnabled,
                overlayItemCount: liveDanmakuRenderStore.itemCount,
                hasPresentedPlayback: playerViewModel?.hasPresentedPlayback == true
            )
        )
    }

    func publishLiveDanmakuDiagnosticsIfNeeded(force: Bool = false) {
        guard force || isLiveDanmakuDiagnosticsEnabled else { return }
        liveDanmakuRenderStore.updateDiagnostics(liveDanmakuDiagnosticsDraft)
    }
}
