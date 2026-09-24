import Foundation

extension PlaybackNetworkDiagnosticsSheet {
    func copyDiagnostics() {
        PlaybackNetworkDiagnosticsCopyAction.copy(diagnosticsText)
        let token = UUID()
        sheetState.copiedMessageTask?.cancel()
        sheetState.copiedMessageToken = token
        sheetState.copiedMessage = "已复制诊断信息"
        sheetState.copiedMessageTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled,
                  sheetState.copiedMessageToken == token
            else { return }
            sheetState.copiedMessage = nil
            sheetState.copiedMessageTask = nil
            sheetState.copiedMessageToken = nil
        }
    }

    @MainActor
    func probePlaybackCDN() {
        guard !sheetState.isProbingPlaybackCDN else { return }

        let token = UUID()
        let metricsID = diagnosticsStore.metricsID
        let addressFamilyPreference = libraryStore.playbackNetworkAddressFamilyPreference
        let playbackURLs = PlaybackNetworkDiagnosticsURLContext.playbackCDNProbeURLs(
            variant: runtimeContext.variant
        )

        sheetState.playbackCDNProbeTask?.cancel()
        sheetState.playbackCDNProbeToken = token
        sheetState.isProbingPlaybackCDN = true
        sheetState.probeMessage = "正在测试 CDN 线路..."

        sheetState.playbackCDNProbeTask = Task { @MainActor in
            let result = await PlaybackNetworkDiagnosticsProbeAction.run(
                addressFamilyPreference: addressFamilyPreference,
                playbackURLs: playbackURLs
            )
            guard !Task.isCancelled,
                  sheetState.playbackCDNProbeToken == token,
                  diagnosticsStore.metricsID == metricsID
            else { return }

            libraryStore.setPlaybackCDNProbeSnapshot(result.snapshot)
            if let preference = result.recommendedPreference {
                libraryStore.setPlaybackCDNPreference(preference)
            }
            sheetState.probeMessage = result.message
            PlaybackNetworkDiagnosticsActionHandler.refreshPlaybackURLPreferenceSnapshots(
                stateActions: stateActions
            )
            sheetState.isProbingPlaybackCDN = false
            sheetState.playbackCDNProbeTask = nil
            sheetState.playbackCDNProbeToken = nil
        }
    }

    @MainActor
    func cancelPlaybackCDNProbe() {
        sheetState.playbackCDNProbeTask?.cancel()
        sheetState.playbackCDNProbeTask = nil
        sheetState.playbackCDNProbeToken = nil
        sheetState.isProbingPlaybackCDN = false
    }

    @MainActor
    func cancelCopiedMessageTask() {
        sheetState.copiedMessageTask?.cancel()
        sheetState.copiedMessageTask = nil
        sheetState.copiedMessageToken = nil
    }

    @MainActor
    func cancelSheetTasks() {
        cancelPlaybackCDNProbe()
        cancelCopiedMessageTask()
    }

    @MainActor
    func updatePerformanceContext(
        metricsID: String,
        isAutoOptimizationEnabled: Bool
    ) {
        PlaybackNetworkDiagnosticsLifecycleAction.updatePerformanceContext(
            observer: performanceObserver,
            metricsID: metricsID,
            isAutoOptimizationEnabled: isAutoOptimizationEnabled
        )
    }

    @MainActor
    func updateAutoOptimizationContext(isEnabled: Bool) {
        PlaybackNetworkDiagnosticsLifecycleAction.updateAutoOptimizationContext(
            observer: performanceObserver,
            metricsID: diagnosticsStore.metricsID,
            isEnabled: isEnabled
        )
    }

    @MainActor
    func refreshInitialDiagnostics() async {
        await PlaybackNetworkDiagnosticsActionHandler.refreshInitialDiagnostics(
            variant: runtimeContext.variant,
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            stateActions: stateActions
        )
    }

    @MainActor
    func refreshHLSBridgeSourceSnapshots() async {
        await PlaybackNetworkDiagnosticsActionHandler.refreshHLSBridgeSourceSnapshots(
            variant: runtimeContext.variant,
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            stateActions: stateActions
        )
    }
}
