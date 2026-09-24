import Foundation

enum HLSRemoteRangeResponseValidator {
    nonisolated static func validate(
        _ response: URLResponse,
        requestedRange: HTTPByteRange,
        url: URL? = nil
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw HLSBridgeRemoteFailure.httpStatus(httpResponse.statusCode, url: url, range: requestedRange)
        }
        if httpResponse.statusCode == 200, requestedRange.start > 0 {
            throw HLSBridgeRemoteFailure.invalidRangeResponse(statusCode: httpResponse.statusCode, url: url, range: requestedRange)
        }
        if httpResponse.statusCode == 206,
           contentRange(from: httpResponse) != requestedRange {
            throw HLSBridgeRemoteFailure.invalidRangeResponse(statusCode: httpResponse.statusCode, url: url, range: requestedRange)
        }
    }

    private nonisolated static func contentRange(from response: HTTPURLResponse) -> HTTPByteRange? {
        guard let value = response.value(forHTTPHeaderField: "Content-Range")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              value.hasPrefix("bytes ")
        else { return nil }
        let payload = value.dropFirst("bytes ".count)
        let parts = payload.split(separator: "/", maxSplits: 1).map(String.init)
        return HTTPByteRange(rawValue: parts.first)
    }
}
