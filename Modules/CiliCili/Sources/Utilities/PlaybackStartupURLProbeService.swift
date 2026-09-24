import Foundation

enum PlaybackStartupURLProbeService {
    struct Selection: Sendable {
        let variant: PlayVariant
        let videoElapsedMilliseconds: Int?
        let audioElapsedMilliseconds: Int?
        let startupValidated: Bool
    }

    private struct ProbeResult: Sendable {
        let url: URL
        let elapsedMilliseconds: Int
    }

    private enum ProbeOutcome: Sendable {
        case success(ProbeResult)
        case failure
        case timeout
    }

    private struct ThroughputResult: Sendable {
        let url: URL
        let elapsedMilliseconds: Int
        let bytes: Int64
    }

    private enum ThroughputOutcome: Sendable {
        case success(ThroughputResult)
        case failure(URL)
    }

    private static let candidateLimit = 3
    private static let requestTimeout: TimeInterval = 0.65
    private static let startupRangeProbeLimit: Int64 = 96 * 1024
    private static let throughputCandidateLimit = 4

    static func optimizedVariant(
        for variant: PlayVariant,
        cdnPreference: PlaybackCDNPreference,
        headers: [String: String],
        timeout: TimeInterval
    ) async -> Selection {
        async let videoSelection = fastestURL(
            from: candidateURLs(
                primary: variant.videoURL,
                backups: variant.videoStream?.backupPlayURLs(cdnPreference: cdnPreference) ?? [],
                limit: candidateLimit
            ),
            stream: variant.videoStream,
            headers: headers,
            timeout: timeout
        )
        async let audioSelection = fastestURL(
            from: candidateURLs(
                primary: variant.audioURL,
                backups: variant.audioStream?.backupPlayURLs(cdnPreference: cdnPreference) ?? [],
                limit: candidateLimit
            ),
            stream: variant.audioStream,
            headers: headers,
            timeout: timeout
        )

        let (video, audio) = await (videoSelection, audioSelection)
        let startupValidated = video != nil && (variant.audioURL == nil || audio != nil)
        return Selection(
            variant: variant.replacingPlaybackURLs(
                videoURL: video?.url ?? variant.videoURL,
                audioURL: audio?.url ?? variant.audioURL
            ),
            videoElapsedMilliseconds: video?.elapsedMilliseconds,
            audioElapsedMilliseconds: audio?.elapsedMilliseconds,
            startupValidated: startupValidated
        )
    }

    static func rankVariantCandidates(
        for variant: PlayVariant,
        cdnPreference: PlaybackCDNPreference,
        headers: [String: String]
    ) async {
        let environment = PlaybackEnvironment.current
        guard !environment.shouldPreferConservativePlayback else { return }

        await rankURLs(
            candidateURLs(
                primary: variant.videoURL,
                backups: variant.videoStream?.backupPlayURLs(cdnPreference: cdnPreference) ?? [],
                limit: throughputCandidateLimit
            ),
            headers: headers,
            byteLimit: environment.networkClass == .wifi ? 512 * 1024 : 256 * 1024,
            timeout: 1.8
        )

        if variant.audioURL != nil {
            await rankURLs(
                candidateURLs(
                    primary: variant.audioURL,
                    backups: variant.audioStream?.backupPlayURLs(cdnPreference: cdnPreference) ?? [],
                    limit: throughputCandidateLimit
                ),
                headers: headers,
                byteLimit: 128 * 1024,
                timeout: 1.4
            )
        }
    }

    private static func candidateURLs(primary: URL?, backups: [URL], limit: Int) -> [URL] {
        var seen = Set<String>()
        return ([primary].compactMap { $0 } + backups)
            .filter { seen.insert($0.absoluteString).inserted }
            .prefix(limit)
            .map { $0 }
    }

    private static func fastestURL(
        from urls: [URL],
        stream: DASHStream?,
        headers: [String: String],
        timeout: TimeInterval
    ) async -> ProbeResult? {
        guard let stream,
              stream.segmentBase?.initializationByteRange != nil,
              stream.segmentBase?.indexByteRange != nil
        else {
            return await fastestConnectivityURL(from: urls, headers: headers, timeout: timeout)
        }
        guard !urls.isEmpty else { return nil }
        return await withTaskGroup(of: ProbeOutcome.self, returning: ProbeResult?.self) { group in
            for url in urls {
                group.addTask(priority: .userInitiated) {
                    await startupRangeProbe(url: url, stream: stream, headers: headers)
                }
            }
            group.addTask(priority: .utility) {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .timeout
            }

            while let outcome = await group.next() {
                switch outcome {
                case .success(let result):
                    group.cancelAll()
                    return result
                case .timeout:
                    group.cancelAll()
                    return nil
                case .failure:
                    continue
                }
            }
            return nil
        }
    }

    private static func fastestConnectivityURL(
        from urls: [URL],
        headers: [String: String],
        timeout: TimeInterval
    ) async -> ProbeResult? {
        guard urls.count > 1 else { return nil }
        return await withTaskGroup(of: ProbeOutcome.self, returning: ProbeResult?.self) { group in
            for url in urls {
                group.addTask(priority: .userInitiated) {
                    await probe(url: url, headers: headers)
                }
            }
            group.addTask(priority: .utility) {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .timeout
            }

            while let outcome = await group.next() {
                switch outcome {
                case .success(let result):
                    group.cancelAll()
                    return result
                case .timeout:
                    group.cancelAll()
                    return nil
                case .failure:
                    continue
                }
            }
            return nil
        }
    }

    private static func startupRangeProbe(url: URL, stream: DASHStream, headers: [String: String]) async -> ProbeOutcome {
        guard let segmentBase = stream.segmentBase,
              let initialization = segmentBase.initializationByteRange,
              let indexRange = segmentBase.indexByteRange
        else {
            return await probe(url: url, headers: headers)
        }

        let start = Date()
        let ranges = [
            cappedProbeRange(initialization),
            cappedProbeRange(indexRange)
        ]
        for range in ranges {
            guard await probeRange(url: url, range: range, headers: headers) else {
                PlaybackURLPreferenceStore.shared.record(
                    url: url,
                    elapsedMilliseconds: requestTimeout * 1000,
                    bytes: 0,
                    succeeded: false
                )
                return .failure
            }
        }

        let elapsed = max(Int(Date().timeIntervalSince(start) * 1000), 1)
        PlaybackURLPreferenceStore.shared.record(
            url: url,
            elapsedMilliseconds: Double(elapsed),
            bytes: ranges.reduce(Int64(0)) { $0 + $1.length },
            succeeded: true
        )
        return .success(ProbeResult(url: url, elapsedMilliseconds: elapsed))
    }

    private static func cappedProbeRange(_ range: HTTPByteRange) -> HTTPByteRange {
        HTTPByteRange(
            start: range.start,
            endInclusive: min(range.endInclusive, range.start + startupRangeProbeLimit - 1)
        )
    }

    private static func probeRange(url: URL, range: HTTPByteRange, headers: [String: String]) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = requestTimeout
        request.networkServiceType = .responsiveData
        request.setValue("bytes=\(range.start)-\(range.endInclusive)", forHTTPHeaderField: "Range")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await BiliNetworkRetry.data(
                sessionProvider: { BiliPlaybackNetworkSessionPool.shared.playbackProbeSession() },
                request: request,
                policy: .playbackProbe
            )
            guard !Task.isCancelled,
                  !data.isEmpty,
                  let httpResponse = response as? HTTPURLResponse
            else { return false }
            if httpResponse.statusCode == 206 {
                return true
            }
            return httpResponse.statusCode == 200
                && range.start == 0
                && Int64(data.count) <= range.length + 16
        } catch {
            return false
        }
    }

    private static func probe(url: URL, headers: [String: String]) async -> ProbeOutcome {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = requestTimeout
        request.networkServiceType = .responsiveData
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let start = Date()
        do {
            let (_, response) = try await BiliNetworkRetry.data(
                sessionProvider: { BiliPlaybackNetworkSessionPool.shared.playbackProbeSession() },
                request: request,
                policy: .playbackProbe
            )
            guard !Task.isCancelled else { return .failure }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<400).contains(statusCode) else { return .failure }
            PlaybackURLPreferenceStore.shared.record(
                url: url,
                elapsedMilliseconds: Double(Int(Date().timeIntervalSince(start) * 1000)),
                bytes: 1,
                succeeded: true
            )
            return .success(
                ProbeResult(
                    url: url,
                    elapsedMilliseconds: Int(Date().timeIntervalSince(start) * 1000)
                )
            )
        } catch {
            PlaybackURLPreferenceStore.shared.record(
                url: url,
                elapsedMilliseconds: requestTimeout * 1000,
                bytes: 0,
                succeeded: false
            )
            return .failure
        }
    }

    private static func rankURLs(
        _ urls: [URL],
        headers: [String: String],
        byteLimit: Int,
        timeout: TimeInterval
    ) async {
        let candidates = Array(urls.prefix(throughputCandidateLimit))
        guard candidates.count > 1 else { return }
        for url in candidates {
            guard !Task.isCancelled else { return }
            let outcome = await throughputProbe(
                url: url,
                headers: headers,
                byteLimit: byteLimit,
                timeout: timeout
            )
            switch outcome {
            case .success(let result):
                PlaybackURLPreferenceStore.shared.record(
                    url: result.url,
                    elapsedMilliseconds: Double(result.elapsedMilliseconds),
                    bytes: result.bytes,
                    succeeded: true
                )
            case .failure(let url):
                PlaybackURLPreferenceStore.shared.record(
                    url: url,
                    elapsedMilliseconds: timeout * 1000,
                    bytes: 0,
                    succeeded: false
                )
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    private static func throughputProbe(
        url: URL,
        headers: [String: String],
        byteLimit: Int,
        timeout: TimeInterval
    ) async -> ThroughputOutcome {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeout
        request.networkServiceType = .responsiveData
        request.setValue("bytes=0-\(max(byteLimit - 1, 0))", forHTTPHeaderField: "Range")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let start = Date()
        do {
            let (data, response) = try await BiliNetworkRetry.data(
                sessionProvider: { BiliPlaybackNetworkSessionPool.shared.playbackProbeSession() },
                request: request,
                policy: .playbackProbe
            )
            guard !Task.isCancelled else { return .failure(url) }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<400).contains(statusCode) else { return .failure(url) }
            let elapsed = max(Int(Date().timeIntervalSince(start) * 1000), 1)
            return .success(
                ThroughputResult(
                    url: url,
                    elapsedMilliseconds: elapsed,
                    bytes: Int64(min(data.count, byteLimit))
                )
            )
        } catch {
            return .failure(url)
        }
    }
}
