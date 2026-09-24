import Foundation
import QuartzCore

extension BiliAPIClient {
    func makePiliPlusWebpageHedge(
        bvid: String,
        page: Int?,
        delayNanoseconds: UInt64
    ) -> PiliPlusWebpageHedge {
        let scheduledAt = CACurrentMediaTime()
        let delayMilliseconds = Double(delayNanoseconds) / 1_000_000
        let task = Task<PlayURLData, Error>(priority: .userInitiated) { [self] in
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    await recordStartupSchedulerMessage(
                        Self.piliPlusWebpageHedgeDiagnosticMessage(
                            event: "webpageHedgeCancelled",
                            delayMilliseconds: delayMilliseconds,
                            elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: scheduledAt),
                            phase: "beforeStart"
                        ),
                        bvid: bvid
                    )
                    throw error
                }
            }

            let requestStart = CACurrentMediaTime()
            await recordStartupSchedulerMessage(
                Self.piliPlusWebpageHedgeDiagnosticMessage(
                    event: "webpageHedgeStart",
                    delayMilliseconds: delayMilliseconds,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: scheduledAt)
                ),
                bvid: bvid
            )
            do {
                try Task.checkCancellation()
                let data = try await fetchPiliPlusUncachedWebPagePlayURL(
                    bvid: bvid,
                    page: page
                )
                await recordStartupSchedulerMessage(
                    Self.piliPlusWebpageHedgeDiagnosticMessage(
                        event: "webpageHedgeReady",
                        delayMilliseconds: delayMilliseconds,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: scheduledAt)
                    ),
                    bvid: bvid
                )
                return data
            } catch {
                let isCancellation =
                    Task.isCancelled
                    || error is CancellationError
                    || (error as? URLError)?.code == .cancelled
                await recordStartupSchedulerMessage(
                    Self.piliPlusWebpageHedgeDiagnosticMessage(
                        event: isCancellation ? "webpageHedgeCancelled" : "webpageHedgeFailed",
                        delayMilliseconds: delayMilliseconds,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: scheduledAt),
                        phase: isCancellation ? "inFlight" : "request",
                        requestElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: requestStart)
                    ),
                    bvid: bvid
                )
                throw error
            }
        }
        return PiliPlusWebpageHedge(
            scheduledAt: scheduledAt,
            delayNanoseconds: delayNanoseconds,
            task: task
        )
    }

    private func fetchPiliPlusUncachedWebPagePlayURL(
        bvid: String,
        page: Int?
    ) async throws -> PlayURLData {
        let snapshot = requestSnapshot(purpose: .playback)
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let data = try await fetchWebPagePlayInfo(
            bvid: bvid,
            page: page,
            referer: referer,
            cookieHeader: snapshot.cookieHeader
        )
        return await applyingConfiguredHistoryAccount(
            to: data,
            playbackUserMID: snapshot.currentUserMID
        )
    }

    func fetchPiliPlusStyleStartupFallbackPlayURL(
        bvid: String,
        cid: Int,
        page: Int?,
        requestedQuality: Int,
        webpageHedge: PiliPlusWebpageHedge? = nil
    ) async throws -> PlayURLData {
        _ = cid
        let webpageHedge =
            webpageHedge
            ?? makePiliPlusWebpageHedge(
                bvid: bvid,
                page: page,
                delayNanoseconds: 0
            )
        let webpageStart = webpageHedge.scheduledAt
        let webpageTask = webpageHedge.task
        defer { webpageTask.cancel() }
        do {
            let webpageData = try await Self.awaitSharedTask(webpageTask)
            await recordStartupSchedulerMessage(
                Self.piliPlusWebpageHedgeDiagnosticMessage(
                    event: "webpageHedgeWon",
                    delayMilliseconds: Double(webpageHedge.delayNanoseconds) / 1_000_000,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: webpageStart)
                ),
                bvid: bvid
            )
            await recordStartupSchedulerMessage(
                Self.piliPlusStartupFallbackDiagnosticMessage(
                    result: "success",
                    route: "webpage",
                    requestedQuality: requestedQuality,
                    selectedQuality: Self.startupCandidateQuality(
                        in: webpageData,
                        requestedQuality: requestedQuality
                    ),
                    legacyResult: "skipped",
                    legacyElapsedMilliseconds: nil,
                    standardWBIResult: "notStarted",
                    standardWBIQuality: nil,
                    standardWBIElapsedMilliseconds: nil,
                    webpageElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: webpageStart),
                    totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: webpageStart)
                ),
                bvid: bvid
            )
            return webpageData
        } catch {
            guard !Task.isCancelled else { throw error }
            await recordStartupSchedulerMessage(
                Self.piliPlusStartupFallbackDiagnosticMessage(
                    result: "failure",
                    route: "webpage",
                    requestedQuality: requestedQuality,
                    selectedQuality: nil,
                    legacyResult: "skipped",
                    legacyElapsedMilliseconds: nil,
                    standardWBIResult: "notStarted",
                    standardWBIQuality: nil,
                    standardWBIElapsedMilliseconds: nil,
                    webpageElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: webpageStart),
                    totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: webpageStart),
                    webpageError: error
                ),
                bvid: bvid
            )
            throw error
        }
    }

    nonisolated static func piliPlusWebpageHedgeDiagnosticMessage(
        event: String,
        delayMilliseconds: Double,
        elapsedMilliseconds: Double,
        phase: String? = nil,
        requestElapsedMilliseconds: Double? = nil
    ) -> String {
        var parts = [
            "piliPlusWebpageHedge",
            "event=\(event)",
            "strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)",
            "delay=\(Int(delayMilliseconds.rounded()))ms",
            "elapsed=\(Int(elapsedMilliseconds.rounded()))ms",
        ]
        if let phase {
            parts.append("phase=\(phase)")
        }
        if let requestElapsedMilliseconds {
            parts.append("request=\(Int(requestElapsedMilliseconds.rounded()))ms")
        }
        return parts.joined(separator: " ")
    }

    nonisolated static func piliPlusWebpageStreamDiagnosticMessage(
        mode: String,
        receivedBytes: Int,
        expectedBytes: Int64?,
        elapsedMilliseconds: Double,
        fallbackReason: String? = nil
    ) -> String {
        var parts = [
            "piliPlusWebpageStream",
            "mode=\(mode)",
            "strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)",
            "received=\(receivedBytes)",
            "expected=\(expectedBytes.map(String.init) ?? "-")",
            "elapsed=\(Int(elapsedMilliseconds.rounded()))ms",
        ]
        if let expectedBytes, expectedBytes > Int64(receivedBytes) {
            parts.append("saved=\(expectedBytes - Int64(receivedBytes))")
        }
        if let fallbackReason {
            parts.append("fallbackReason=\(fallbackReason)")
        }
        return parts.joined(separator: " ")
    }
}

nonisolated struct PiliPlusWebpageHedge: Sendable {
    let scheduledAt: CFTimeInterval
    let delayNanoseconds: UInt64
    let task: Task<PlayURLData, Error>
}
