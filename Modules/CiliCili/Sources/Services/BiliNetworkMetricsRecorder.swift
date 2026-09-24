import Foundation
import OSLog

nonisolated final class BiliNetworkMetricsRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let logger = Logger(subsystem: "cc.bili", category: "NetworkMetrics")

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        guard let transaction = metrics.transactionMetrics.last,
            let url = transaction.request.url
        else { return }

        let host = url.host ?? "-"
        let path = Self.metricsPath(for: url)
        let duration = max(0, metrics.taskInterval.duration)
        let protocolName = transaction.networkProtocolName ?? "-"
        let dnsMilliseconds = Self.intervalMilliseconds(
            from: transaction.domainLookupStartDate,
            to: transaction.domainLookupEndDate
        )
        let connectMilliseconds = Self.intervalMilliseconds(
            from: transaction.connectStartDate,
            to: transaction.connectEndDate
        )
        let tlsMilliseconds = Self.intervalMilliseconds(
            from: transaction.secureConnectionStartDate,
            to: transaction.secureConnectionEndDate
        )
        let ttfbMilliseconds = Self.intervalMilliseconds(
            from: transaction.requestStartDate,
            to: transaction.responseStartDate
        )
        let totalMilliseconds = Int((duration * 1000).rounded())
        let reused = transaction.isReusedConnection ? "reuse" : "new"
        let message =
            "host=\(host) path=\(path) proto=\(protocolName) \(reused) total=\(totalMilliseconds)ms dns=\(dnsMilliseconds)ms conn=\(connectMilliseconds)ms tls=\(tlsMilliseconds)ms ttfb=\(ttfbMilliseconds)ms"

        logger.info("\(message, privacy: .public)")

        guard let metricsID = Self.metricsID(for: url) else { return }
        Task { @MainActor in
            PlayerPerformanceStore.shared.record(
                .network,
                metricsID: metricsID,
                title: nil,
                message: message
            )
        }
    }

    private nonisolated static func intervalMilliseconds(from start: Date?, to end: Date?) -> Int {
        guard let start, let end else { return 0 }
        return max(0, Int((end.timeIntervalSince(start) * 1000).rounded()))
    }

    private nonisolated static func metricsPath(for url: URL) -> String {
        guard url.host?.contains("bilibili.com") == true else {
            return url.path.isEmpty ? "/" : url.path
        }
        if url.path == "/x/player/playurl" || url.path == "/x/player/wbi/playurl" {
            return "playurl"
        }
        if url.path == "/x/web-interface/view" {
            return "detail"
        }
        if url.path == "/x/web-interface/archive/related" {
            return "related"
        }
        if url.path == "/x/v2/reply/main" {
            return "comments"
        }
        if url.path == "/video/" || url.path.contains("/video/") {
            return "webpage"
        }
        return url.path.isEmpty ? "/" : url.path
    }

    private nonisolated static func metricsID(for url: URL) -> String? {
        if let bvid = queryValue("bvid", in: url), !bvid.isEmpty {
            return bvid
        }
        let path = url.path
        if let range = path.range(of: #"BV[A-Za-z0-9]+"#, options: .regularExpression) {
            return String(path[range])
        }
        return nil
    }

    private nonisolated static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
