import Foundation
import Network

nonisolated final class HLSProxyFailureStore: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var value: (reason: HLSBridgeFailureReason, date: Date)?

    nonisolated func record(_ error: Error, now: Date = Date()) {
        record(HLSBridgeRemoteFailure.reason(for: error), now: now)
    }

    nonisolated func record(_ reason: HLSBridgeFailureReason, now: Date = Date()) {
        lock.lock()
        value = (reason, now)
        lock.unlock()
    }

    nonisolated func recentReason(maxAge: TimeInterval = 12, now: Date = Date()) -> HLSBridgeFailureReason? {
        lock.lock()
        defer { lock.unlock() }
        guard let value,
              now.timeIntervalSince(value.date) <= maxAge
        else { return nil }
        return value.reason
    }
}

extension Array where Element == URL {
    nonisolated func removingDuplicates() -> [URL] {
        var seen = Set<String>()
        var result = [URL]()
        for url in self {
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            result.append(url)
        }
        return result
    }
}

extension Array {
    nonisolated subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct HLSProxyRequest: Sendable {
    let method: String
    let path: String
    let range: HTTPByteRange?
    let shouldCloseConnection: Bool

    nonisolated init?(data: Data) {
        guard let rawRequest = String(data: data, encoding: .utf8) else { return nil }
        let lines = rawRequest.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else { return nil }

        method = requestParts[0]
        let rawPath = requestParts[1]
        let httpVersion = requestParts.indices.contains(2) ? requestParts[2].lowercased() : "http/1.0"
        path = URLComponents(string: "http://127.0.0.1\(rawPath)")?.path ?? rawPath

        var parsedRange: HTTPByteRange?
        var connectionValue: String?
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "range":
                parsedRange = HTTPByteRange(httpHeaderValue: value)
            case "connection":
                connectionValue = value.lowercased()
            default:
                break
            }
        }
        range = parsedRange
        if connectionValue?.contains("close") == true {
            shouldCloseConnection = true
        } else if httpVersion == "http/1.1" {
            shouldCloseConnection = false
        } else {
            shouldCloseConnection = connectionValue?.contains("keep-alive") != true
        }
    }
}

struct HLSProxyHTTPResponse: Sendable {
    let statusLine: String
    let headers: [String: String]

    nonisolated var headerData: Data {
        let headerText = ([statusLine] + headers.map { "\($0.key): \($0.value)" })
            .joined(separator: "\r\n") + "\r\n\r\n"
        return Data(headerText.utf8)
    }
}

enum HLSProxyHTTPResponseBuilder {
    nonisolated static func dataResponse(
        contentType: String,
        request: HLSProxyRequest,
        responseLength: Int64,
        totalLength: Int64? = nil,
        servedRange: HTTPByteRange? = nil,
        closesConnection: Bool = true
    ) -> HLSProxyHTTPResponse {
        var headers = [
            "Content-Type": contentType,
            "Content-Length": "\(max(responseLength, 0))",
            "Accept-Ranges": "bytes",
            "Cache-Control": request.path.hasSuffix(".m3u8") ? "no-cache" : "public, max-age=3600",
            "Connection": closesConnection ? "close" : "keep-alive"
        ]
        let statusLine: String
        if let servedRange, let totalLength {
            statusLine = "HTTP/1.1 206 Partial Content"
            headers["Content-Range"] = "bytes \(servedRange.start)-\(servedRange.endInclusive)/\(totalLength)"
        } else {
            statusLine = "HTTP/1.1 200 OK"
        }
        return HLSProxyHTTPResponse(statusLine: statusLine, headers: headers)
    }

    nonisolated static func errorResponse(statusCode: Int, reason: String) -> (response: HLSProxyHTTPResponse, body: Data) {
        let body = Data(reason.utf8)
        let response = HLSProxyHTTPResponse(
            statusLine: "HTTP/1.1 \(statusCode) \(reason)",
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
                "Content-Length": "\(body.count)",
                "Connection": "close"
            ]
        )
        return (response, body)
    }
}

enum HLSLoopbackEndpointPolicy {
    nonisolated static func tcpListenerParameters() throws -> NWParameters {
        guard let address = IPv4Address("127.0.0.1") else {
            throw PlayerEngineError.unsupportedMedia
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(address), port: .any)
        return parameters
    }

    nonisolated static func allows(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        let value = "\(host)".lowercased()
        return value == "127.0.0.1" || value == "::1" || value == "localhost"
    }
}
