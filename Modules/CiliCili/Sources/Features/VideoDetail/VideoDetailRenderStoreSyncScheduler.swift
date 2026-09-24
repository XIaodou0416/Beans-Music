import Foundation

extension VideoDetailViewModel {
    func scheduleRenderStoreSync(_ syncs: VideoDetailRenderStoreSyncMask) {
        guard !syncs.isEmpty else { return }
        pendingRenderStoreSyncs.formUnion(syncs)
        guard renderStoreSyncTask == nil else { return }
        let syncGeneration = advanceRenderStoreSyncGeneration()
        renderStoreSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.renderStoreSyncCoalescingDelayNanoseconds)
            guard let self,
                  !Task.isCancelled,
                  self.renderStoreSyncGeneration == syncGeneration
            else { return }
            self.flushScheduledRenderStoreSyncs(generation: syncGeneration)
        }
    }

    func flushScheduledRenderStoreSyncs(generation: Int? = nil) {
        if let generation {
            guard renderStoreSyncGeneration == generation else { return }
        }
        let syncs = pendingRenderStoreSyncs
        pendingRenderStoreSyncs = []
        renderStoreSyncTask = nil
        syncRenderStores(syncs)
    }

    @discardableResult
    func advanceRenderStoreSyncGeneration() -> Int {
        renderStoreSyncGeneration += 1
        return renderStoreSyncGeneration
    }

    func syncRenderStores(_ syncs: VideoDetailRenderStoreSyncMask) {
        if syncs.contains(.interaction) {
            syncInteractionRenderStore()
        }
        if syncs.contains(.playback) {
            syncPlaybackRenderStore()
        }
        if syncs.contains(.favoriteFolder) {
            syncFavoriteFolderRenderStore()
        }
        if syncs.contains(.danmakuSettings) {
            syncDanmakuSettingsRenderStore()
        }
        if syncs.contains(.networkDiagnostics) {
            syncNetworkDiagnosticsRenderStore()
        }
        if syncs.contains(.description) {
            syncDescriptionRenderStore()
        }
        if syncs.contains(.playerIdentity) {
            syncPlayerIdentityRenderStore()
        }
        if syncs.contains(.danmaku) {
            syncDanmakuRenderStore()
        }
    }
}
