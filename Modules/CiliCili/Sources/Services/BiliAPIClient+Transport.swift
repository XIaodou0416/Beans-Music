import CryptoKit
import Foundation
import Security

extension BiliAPIClient {
    func transportSession() -> URLSession {
        session
    }

    func get<T: Decodable & Sendable>(
        base: URL,
        path: String,
        query: [String: String],
        referer: String = "https://www.bilibili.com",
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        additionalHeaders: [String: String] = [:],
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        responseCachePolicy: BiliAPIResponseCachePolicy? = nil,
        priority: Float = URLSessionTask.defaultPriority,
        timeoutInterval: TimeInterval? = nil,
        responseDataObserver: (@Sendable (Data) -> Void)? = nil
    ) async throws -> T {
        var request = try await makeRequest(
            base: base,
            path: path,
            query: query,
            referer: referer,
            userAgent: userAgent,
            cookieHeader: cookieHeader,
            additionalHeaders: additionalHeaders,
            cachePolicy: cachePolicy
        )
        request.networkServiceType = priority >= URLSessionTask.highPriority ? .responsiveData : .default
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        let responseCacheKey = responseCachePolicy.flatMap { _ in Self.responseCacheKey(for: request) }
        if responseCachePolicy != nil,
            let responseCacheKey,
            let cachedData = await BiliAPIResponseMemoryCache.shared.freshData(for: responseCacheKey)
        {
            guard !cachedData.isEmpty else { throw BiliAPIError.emptyData }
            return try await Self.decode(cachedData, priority: priority)
        }

        if let responseCachePolicy,
            responseCachePolicy.staleTTL > responseCachePolicy.freshTTL,
            cachePolicy != .reloadIgnoringLocalCacheData,
            let responseCacheKey,
            let staleData = await BiliAPIResponseMemoryCache.shared.staleData(for: responseCacheKey),
            let decoded: T = try? await Self.decode(staleData, priority: priority)
        {
            refreshResponseCacheInBackground(
                request,
                cacheKey: responseCacheKey,
                policy: responseCachePolicy,
                priority: priority,
                responseDataObserver: responseDataObserver
            )
            return decoded
        }

        do {
            let data = try await readData(for: request, priority: priority)
            guard !data.isEmpty else { throw BiliAPIError.emptyData }
            let decoded: T = try await Self.decode(data, priority: priority)
            if let responseCachePolicy, let responseCacheKey {
                await BiliAPIResponseMemoryCache.shared.store(
                    data,
                    for: responseCacheKey,
                    policy: responseCachePolicy
                )
            }
            responseDataObserver?(data)
            return decoded
        } catch {
            if let responseCachePolicy,
                responseCachePolicy.staleTTL > responseCachePolicy.freshTTL,
                let responseCacheKey,
                let staleData = await BiliAPIResponseMemoryCache.shared.staleData(for: responseCacheKey),
                let decoded: T = try? await Self.decode(staleData, priority: priority)
            {
                return decoded
            }
            throw error
        }
    }

    func postForm<T: Decodable & Sendable>(
        base: URL,
        path: String,
        body: [String: String],
        referer: String = "https://www.bilibili.com",
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        retryPolicy: BiliNetworkRetryPolicy = .api
    ) async throws -> T {
        var request = try await makeRequest(
            base: base,
            path: path,
            query: [:],
            referer: referer,
            userAgent: userAgent,
            cookieHeader: cookieHeader
        )
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(from: body)
        let (data, _) = try await data(
            for: request,
            priority: URLSessionTask.highPriority,
            retryPolicy: retryPolicy
        )
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        return try await Self.decode(data, priority: URLSessionTask.highPriority)
    }

    func postMultipart<T: Decodable & Sendable>(
        base: URL,
        path: String,
        fields: [String: String],
        fileField: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        referer: String = "https://www.bilibili.com"
    ) async throws -> T {
        let boundary = "CiliCiliBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            body.append(contentsOf: "--\(boundary)\r\n".utf8)
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8)
            body.append(contentsOf: "\(value)\r\n".utf8)
        }
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n".utf8)
        body.append(contentsOf: "Content-Type: \(mimeType)\r\n\r\n".utf8)
        body.append(fileData)
        body.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)

        var request = try await makeRequest(
            base: base,
            path: path,
            query: [:],
            referer: referer,
            cookieHeader: await interactionRequestContext().cookieHeader
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.httpBody = body
        let (data, _) = try await data(
            for: request,
            priority: URLSessionTask.highPriority,
            retryPolicy: .api
        )
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        return try await Self.decode(data, priority: URLSessionTask.highPriority)
    }

    func postSignedAPIForm<T: Decodable & Sendable>(
        path: String,
        fields: [String: String],
        profile: BiliAppSigner.Profile,
        cookieHeader: String,
        additionalHeaders: [String: String]
    ) async throws -> T {
        var request = try await makeRequest(
            base: baseURL,
            path: path,
            query: [:],
            referer: "https://space.bilibili.com",
            userAgent: profile.userAgent,
            cookieHeader: cookieHeader,
            additionalHeaders: additionalHeaders,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(from: BiliAppSigner.sign(fields, profile: profile))
        let (data, _) = try await data(for: request, priority: URLSessionTask.highPriority)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        return try await Self.decode(data, priority: URLSessionTask.highPriority)
    }

    func makeRequest(
        base: URL,
        path: String,
        query: [String: String],
        referer: String = "https://www.bilibili.com",
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        additionalHeaders: [String: String] = [:],
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> URLRequest {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw BiliAPIError.invalidURL
        }
        components.path = path
        if !query.isEmpty {
            components.queryItems =
                query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw BiliAPIError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        let resolvedCookieHeader: String
        if let cookieHeader {
            resolvedCookieHeader = cookieHeader
        } else {
            resolvedCookieHeader = await transportRequestContext().cookieHeader
        }
        applyCommonHeaders(
            to: &request,
            referer: referer,
            userAgent: userAgent,
            cookieHeader: resolvedCookieHeader
        )
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if cachePolicy != .useProtocolCachePolicy {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }
        return request
    }

    func data(
        for request: URLRequest,
        priority: Float = URLSessionTask.defaultPriority,
        retryPolicy: BiliNetworkRetryPolicy = .api
    ) async throws -> (Data, URLResponse) {
        var request = request
        request.networkServiceType = priority >= URLSessionTask.highPriority ? .responsiveData : .default
        let response = try await BiliNetworkRetry.data(
            session: transportSession(),
            request: request,
            priority: priority,
            policy: retryPolicy
        )
        ResourceCacheAutoTrim.schedule()
        return response
    }

    func requireCSRF() async throws -> String {
        try await requireCSRFContext(for: .main).csrf
    }

    static func formBody(from fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    nonisolated static func randomAlphaNumeric(length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(length))
        }
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    nonisolated static func cookieValue(named name: String, in header: String) -> String? {
        header
            .split(separator: ";")
            .compactMap { item -> String? in
                let pair = item.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard pair.count == 2, pair[0] == name, !pair[1].isEmpty else { return nil }
                return pair[1]
            }
            .first
    }

    nonisolated static func decode<T: Decodable & Sendable>(
        _ type: T.Type = T.self,
        from data: Data,
        priority: Float
    ) async throws -> T {
        let taskPriority: TaskPriority
        if priority >= URLSessionTask.highPriority {
            taskPriority = .userInitiated
        } else if priority <= URLSessionTask.lowPriority {
            taskPriority = .background
        } else {
            taskPriority = .utility
        }

        return try await Task.detached(priority: taskPriority) {
            try JSONDecoder.bili.decode(T.self, from: data)
        }.value
    }

    nonisolated static func decode<T: Decodable & Sendable>(
        _ data: Data,
        priority: Float
    ) async throws -> T {
        try await decode(T.self, from: data, priority: priority)
    }

    private func refreshResponseCacheInBackground(
        _ request: URLRequest,
        cacheKey: String,
        policy: BiliAPIResponseCachePolicy,
        priority: Float,
        responseDataObserver: (@Sendable (Data) -> Void)?
    ) {
        Task(priority: priority >= URLSessionTask.highPriority ? .userInitiated : .utility) { [self] in
            do {
                let data = try await readData(for: request, priority: priority)
                guard !data.isEmpty else { return }
                await BiliAPIResponseMemoryCache.shared.store(data, for: cacheKey, policy: policy)
                responseDataObserver?(data)
            } catch {
                return
            }
        }
    }

    private func readData(
        for request: URLRequest,
        priority: Float
    ) async throws -> Data {
        guard let key = Self.readRequestCoalescingKey(for: request, priority: priority) else {
            return try await data(for: request, priority: priority).0
        }

        let session = transportSession()
        return try await BiliReadRequestCoalescer.shared.data(for: key) {
            try await Self.performReadRequest(
                session: session,
                request: request,
                priority: priority
            )
        }
    }

    private nonisolated static func performReadRequest(
        session: URLSession,
        request: URLRequest,
        priority: Float
    ) async throws -> Data {
        var request = request
        request.networkServiceType = priority >= URLSessionTask.highPriority ? .responsiveData : .default
        let (data, _) = try await BiliNetworkRetry.data(
            session: session,
            request: request,
            priority: priority,
            policy: .api
        )
        ResourceCacheAutoTrim.schedule()
        return data
    }

    private nonisolated static func readRequestCoalescingKey(
        for request: URLRequest,
        priority: Float
    ) -> String? {
        guard let url = request.url,
            (request.httpMethod ?? "GET").uppercased() == "GET"
        else { return nil }

        let headers = (request.allHTTPHeaderFields ?? [:])
            .map { ($0.key.lowercased(), $0.value) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "\n")
        let material = [
            url.absoluteString,
            "cache=\(request.cachePolicy.rawValue)",
            "timeout=\(request.timeoutInterval)",
            "priority=\(priority)",
            headers,
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func responseCacheKey(for request: URLRequest) -> String? {
        guard let url = request.url else { return nil }
        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
        let referer = request.value(forHTTPHeaderField: "Referer") ?? ""
        let cookieScope = responseCacheCookieScope(request.value(forHTTPHeaderField: "Cookie") ?? "")
        return [
            url.absoluteString,
            "ua:\(userAgent)",
            "ref:\(referer)",
            "cookie:\(cookieScope)",
        ].joined(separator: "\n")
    }

    private nonisolated static func responseCacheCookieScope(_ cookieHeader: String) -> String {
        let mid = cookieValue(named: "DedeUserID", in: cookieHeader) ?? "0"
        let hasSession = cookieValue(named: "SESSDATA", in: cookieHeader) != nil
        let buvid = cookieValue(named: "buvid3", in: cookieHeader) ?? "-"
        return "\(hasSession ? "auth" : "anon")|mid:\(mid)|buvid:\(buvid)"
    }

    private func requireCSRFContext(
        for purpose: BiliAccountPurpose
    ) async throws -> (csrf: String, context: BiliAPITransportRequestContext) {
        let context = await transportRequestContext(purpose: purpose)
        guard context.isLoggedIn else {
            throw BiliAPIError.missingSESSDATA
        }
        guard let csrf = context.csrfToken, !csrf.isEmpty else {
            throw BiliAPIError.missingCSRF
        }
        return (csrf, context)
    }

    private func applyCommonHeaders(
        to request: inout URLRequest,
        referer: String,
        userAgent: String? = nil,
        cookieHeader: String
    ) {
        let headers = BiliURLSessionFactory.apiHeaders(
            referer: referer,
            userAgent: userAgent ?? Self.mobileUserAgent,
            cookieHeader: cookieHeader
        )
        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }
    }

}
