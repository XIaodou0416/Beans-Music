import Foundation

extension VideoDetailViewModel {
    func recordPlaybackRecoveryDecision(
        _ decision: VideoDetailPlaybackRecoveryDecision,
        source: VideoDetailPlaybackRecoveryFailureSource,
        message: String,
        reason: HLSBridgeFailureReason?,
        failedVariant: PlayVariant,
        fallbackVariant: PlayVariant?
    ) {
        var parts = playbackRecoveryMetricParts(
            stage: playbackRecoveryStage(for: decision.action),
            status: playbackRecoveryStatus(for: decision.action),
            source: source,
            attempt: playbackRecoveryAttemptCount,
            failedVariant: failedVariant,
            reason: reason
        )
        if let fallbackVariant {
            parts.append(contentsOf: VideoDetailPlaybackFallbackContext(
                failedVariant: failedVariant,
                fallbackVariant: fallbackVariant
            ).metricParts)
        }
        if decision.shouldRefreshCDN {
            parts.append("cdnRefresh=queued")
        }
        if let ignoreReason = playbackRecoveryIgnoreReason(for: decision.action) {
            parts.append("ignore=\(ignoreReason.rawValue)")
        }
        parts.append("error=\(diagnosticToken(message))")
        PlayerMetricsLog.record(
            .playbackRecovery,
            metricsID: detail.bvid,
            title: detail.title,
            message: parts.joined(separator: " ")
        )
    }

    func recordPlaybackRecoveryStage(
        _ stage: String,
        status: String,
        attempt: Int,
        failedVariant: PlayVariant,
        reason: HLSBridgeFailureReason?,
        extraParts: [String] = []
    ) {
        var parts = playbackRecoveryMetricParts(
            stage: stage,
            status: status,
            source: nil,
            attempt: attempt,
            failedVariant: failedVariant,
            reason: reason
        )
        parts.append(contentsOf: extraParts)
        PlayerMetricsLog.record(
            .playbackRecovery,
            metricsID: detail.bvid,
            title: detail.title,
            message: parts.joined(separator: " ")
        )
    }

    private func playbackRecoveryMetricParts(
        stage: String,
        status: String,
        source: VideoDetailPlaybackRecoveryFailureSource?,
        attempt: Int,
        failedVariant: PlayVariant,
        reason: HLSBridgeFailureReason?
    ) -> [String] {
        var parts = [
            "stage=\(stage)",
            "status=\(status)",
            "attempt=\(attempt)",
            "q=\(failedVariant.quality)",
            "variant=\(diagnosticToken(failedVariant.id))",
            "codec=\(diagnosticToken(failedVariant.codec ?? "-"))",
            "range=\(failedVariant.dynamicRange.rawValue)"
        ]
        if let source {
            parts.append("source=\(source.rawValue)")
        }
        if let reason {
            parts.append("reason=\(reason.category.rawValue)")
            parts.append("layer=\(reason.layer.rawValue)")
            if let statusCode = reason.statusCode {
                parts.append("http=\(statusCode)")
            }
            if let host = reason.urlHost, !host.isEmpty {
                parts.append("host=\(diagnosticToken(host))")
            }
        } else {
            parts.append("reason=message")
        }
        return parts
    }

    private func playbackRecoveryStage(for action: VideoDetailPlaybackRecoveryAction) -> String {
        switch action {
        case .ignore:
            return "ignored"
        case .reloadPlayURL:
            return "reloadScheduled"
        case .switchVariant:
            return "fallbackVariant"
        case .exhausted:
            return "exhausted"
        }
    }

    private func playbackRecoveryStatus(for action: VideoDetailPlaybackRecoveryAction) -> String {
        switch action {
        case .ignore:
            return "ignored"
        case .reloadPlayURL, .switchVariant:
            return "started"
        case .exhausted:
            return "exhausted"
        }
    }

    private func playbackRecoveryIgnoreReason(
        for action: VideoDetailPlaybackRecoveryAction
    ) -> VideoDetailPlaybackRecoveryIgnoreReason? {
        guard case let .ignore(reason) = action else { return nil }
        return reason
    }
}
