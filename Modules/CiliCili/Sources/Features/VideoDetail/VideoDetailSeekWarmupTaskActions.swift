import Foundation

extension VideoDetailViewModel {
    func cancelSeekWarmups(clearRecent: Bool = false) {
        seekWarmupTasks.values.forEach { $0.cancel() }
        seekWarmupTasks.removeAll()
        seekWarmupTokens.removeAll()
        seekWarmupTaskOrder.removeAll()
        if clearRecent {
            recentSeekWarmupKeys.removeAll()
            recentSeekWarmupKeyOrder.removeAll()
        }
    }

    func shouldScheduleSeekWarmup(for key: String) -> Bool {
        guard !recentSeekWarmupKeys.contains(key), seekWarmupTasks[key] == nil else {
            return false
        }
        if !seekWarmupTasks.isEmpty {
            seekWarmupTasks.values.forEach { $0.cancel() }
            seekWarmupTasks.removeAll()
            seekWarmupTokens.removeAll()
            seekWarmupTaskOrder.removeAll()
        }
        while seekWarmupTaskOrder.count >= Self.maxInFlightSeekWarmups,
            let evictedKey = seekWarmupTaskOrder.first {
            seekWarmupTaskOrder.removeFirst()
            seekWarmupTasks[evictedKey]?.cancel()
            seekWarmupTasks[evictedKey] = nil
            seekWarmupTokens[evictedKey] = nil
        }
        return true
    }

    func finishSeekWarmup(for key: String, token: UUID, didWarm: Bool) {
        guard seekWarmupTokens[key] == token else { return }
        seekWarmupTasks[key] = nil
        seekWarmupTokens[key] = nil
        seekWarmupTaskOrder.removeAll { $0 == key }
        guard didWarm else { return }
        rememberRecentSeekWarmup(key)
    }

    func clearSeekWarmupIfCurrent(for key: String, token: UUID) {
        guard seekWarmupTokens[key] == token else { return }
        seekWarmupTasks[key] = nil
        seekWarmupTokens[key] = nil
        seekWarmupTaskOrder.removeAll { $0 == key }
    }

    func seekWarmupKey(
        bvid: String,
        cid: Int,
        page: Int?,
        variants: [PlayVariant],
        playbackTime: TimeInterval
    ) -> String {
        let bucket = Int(max(playbackTime, 0) / Self.seekWarmupBucketDuration)
        return [
            bvid,
            String(cid),
            String(page ?? 0),
            variants.map(\.id).joined(separator: "+"),
            String(bucket)
        ].joined(separator: "|")
    }

    private func rememberRecentSeekWarmup(_ key: String) {
        recentSeekWarmupKeys.insert(key)
        recentSeekWarmupKeyOrder.removeAll { $0 == key }
        recentSeekWarmupKeyOrder.append(key)
        while recentSeekWarmupKeyOrder.count > Self.recentSeekWarmupLimit {
            let evictedKey = recentSeekWarmupKeyOrder.removeFirst()
            recentSeekWarmupKeys.remove(evictedKey)
        }
    }
}
