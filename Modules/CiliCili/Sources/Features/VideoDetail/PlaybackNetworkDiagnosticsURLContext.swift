import Foundation

enum PlaybackNetworkDiagnosticsURLContext {
    static func currentHostSnapshot(
        variant: PlayVariant?,
        snapshots: [PlaybackURLPreferenceSnapshot]
    ) -> PlaybackURLPreferenceSnapshot? {
        guard let host = variant?.videoURL?.host else { return nil }
        let normalizedHost = host.lowercased()
        return snapshots.first { $0.host == normalizedHost }
            ?? PlaybackURLPreferenceStore.shared.snapshot(forHost: normalizedHost)
    }

    static func hlsBridgeCandidateURLs(
        variant: PlayVariant?,
        cdnPreference: PlaybackCDNPreference
    ) -> [URL] {
        guard let variant else { return [] }
        var urls: [URL] = []
        var seen = Set<URL>()

        func append(_ url: URL?) {
            guard let url, seen.insert(url).inserted else { return }
            urls.append(url)
        }

        append(variant.videoURL)
        for url in variant.videoStream?.backupPlayURLs(cdnPreference: cdnPreference) ?? [] {
            append(url)
        }
        append(variant.audioURL)
        for url in variant.audioStream?.backupPlayURLs(cdnPreference: cdnPreference) ?? [] {
            append(url)
        }
        return urls
    }

    static func playbackCDNProbeURLs(variant: PlayVariant?) -> [URL] {
        guard let variant else { return [] }
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL?) {
            guard let url,
                  seen.insert(url.absoluteString).inserted
            else { return }
            urls.append(url)
        }

        append(variant.videoURL)
        append(variant.audioURL)
        return urls
    }
}
