import AVFoundation
import Foundation
import OSLog
import UniformTypeIdentifiers

nonisolated final class BiliHeaderResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let assetURL: URL

    private let originalURL: URL
    private let headers: [String: String]
    private let callbackQueue: DispatchQueue
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private var cacheLookupTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var activeRequests: Set<ObjectIdentifier> = []
    private let session: URLSession

    init(originalURL: URL, headers: [String: String]) {
        self.originalURL = originalURL
        self.headers = headers
        let identifier = UUID().uuidString
        assetURL = URL(string: "bili-resource://asset/\(identifier)/video.mp4")!
        let callbackQueue = DispatchQueue(label: "cc.bili.progressive-resource-loader")
        self.callbackQueue = callbackQueue
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 6
        queue.underlyingQueue = callbackQueue
        session = BiliURLSessionFactory.makePlaybackResourceSession(delegateQueue: queue)
        super.init()
    }

    deinit {
        lock.lock()
        let lookupTasks = Array(cacheLookupTasks.values)
        activeRequests.removeAll()
        cacheLookupTasks.removeAll()
        lock.unlock()
        lookupTasks.forEach { $0.cancel() }
        session.invalidateAndCancel()
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let rangeHeader = rangeHeader(for: loadingRequest)
        let cacheKey = ProgressiveMediaCacheKey(
            url: originalURL.absoluteString,
            rangeHeader: rangeHeader ?? "bytes=0-"
        )
        let identifier = ObjectIdentifier(loadingRequest)
        storeActiveRequest(identifier)
        let lookupTask = Task { [weak self, weak loadingRequest] in
            guard let self, let loadingRequest else { return }
            if let cached = await ProgressiveMediaSegmentCache.shared.response(for: cacheKey) {
                guard !Task.isCancelled,
                      self.isRequestActive(identifier)
                else { return }
                self.removeCacheLookupTask(for: identifier)
                self.finish(loadingRequest, identifier: identifier, with: cached)
                return
            }
            guard !Task.isCancelled,
                  self.isRequestActive(identifier)
            else { return }
            self.removeCacheLookupTask(for: identifier)
            self.startNetworkRequest(
                loadingRequest,
                rangeHeader: rangeHeader,
                cacheKey: cacheKey
            )
        }
        storeCacheLookupTask(lookupTask, for: identifier)
        return true
    }

    private func startNetworkRequest(
        _ loadingRequest: AVAssetResourceLoadingRequest,
        rangeHeader: String?,
        cacheKey: ProgressiveMediaCacheKey
    ) {
        var request = URLRequest(url: originalURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.networkServiceType = .video
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let rangeHeader {
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }

        let identifier = ObjectIdentifier(loadingRequest)
        let task = session.dataTask(with: request) { [weak self, weak loadingRequest] data, response, error in
            guard let self = self, let loadingRequest = loadingRequest else { return }
            self.removeTask(for: identifier)
            guard self.isRequestActive(identifier) else { return }

            if let error = error {
                loadingRequest.finishLoading(with: error)
                self.removeActiveRequest(identifier)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, let data else {
                loadingRequest.finishLoading(with: Self.error(message: "Empty progressive video response."))
                self.removeActiveRequest(identifier)
                return
            }
            guard 200..<300 ~= httpResponse.statusCode else {
                let message = "Progressive video HTTP \(httpResponse.statusCode)."
                PlayerMetricsLog.logger.error("progressiveProxyHTTPError status=\(httpResponse.statusCode, privacy: .public)")
                loadingRequest.finishLoading(with: Self.error(code: httpResponse.statusCode, message: message))
                self.removeActiveRequest(identifier)
                return
            }

            let cachedResponse = ProgressiveMediaCacheResponse(
                data: data,
                contentLength: self.contentLength(from: httpResponse, dataLength: data.count),
                mimeType: httpResponse.mimeType,
                isByteRangeAccessSupported: true
            )
            self.fillContentInformation(loadingRequest.contentInformationRequest, cachedResponse: cachedResponse)
            loadingRequest.dataRequest?.respond(with: cachedResponse.data)
            loadingRequest.finishLoading()
            self.removeActiveRequest(identifier)
            Task {
                await ProgressiveMediaSegmentCache.shared.store(cachedResponse, for: cacheKey)
            }
        }
        if store(task, for: identifier) {
            task.resume()
        } else {
            task.cancel()
        }
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let identifier = ObjectIdentifier(loadingRequest)
        lock.lock()
        let task = tasks.removeValue(forKey: identifier)
        let lookupTask = cacheLookupTasks.removeValue(forKey: identifier)
        activeRequests.remove(identifier)
        lock.unlock()
        task?.cancel()
        lookupTask?.cancel()
    }

    private func rangeHeader(for loadingRequest: AVAssetResourceLoadingRequest) -> String? {
        guard let dataRequest = loadingRequest.dataRequest else {
            return loadingRequest.contentInformationRequest == nil ? nil : "bytes=0-1"
        }
        let start = dataRequest.currentOffset > 0 ? dataRequest.currentOffset : dataRequest.requestedOffset
        let length = Int64(dataRequest.requestedLength)
        guard start >= 0, length > 0 else { return nil }
        return "bytes=\(start)-\(start + length - 1)"
    }

    private func fillContentInformation(
        _ contentInformationRequest: AVAssetResourceLoadingContentInformationRequest?,
        response: HTTPURLResponse,
        dataLength: Int
    ) {
        guard let contentInformationRequest = contentInformationRequest else { return }
        contentInformationRequest.isByteRangeAccessSupported = true
        contentInformationRequest.contentLength = contentLength(from: response, dataLength: dataLength)
        if let mimeType = response.mimeType,
           let type = UTType(mimeType: mimeType) ?? UTType(mimeType: mimeType, conformingTo: .movie) {
            contentInformationRequest.contentType = type.identifier
        } else if let type = UTType(filenameExtension: "mp4") {
            contentInformationRequest.contentType = type.identifier
        }
    }

    private func finish(
        _ loadingRequest: AVAssetResourceLoadingRequest,
        identifier: ObjectIdentifier,
        with cachedResponse: ProgressiveMediaCacheResponse
    ) {
        callbackQueue.async {
            guard self.isRequestActive(identifier) else { return }
            self.fillContentInformation(loadingRequest.contentInformationRequest, cachedResponse: cachedResponse)
            loadingRequest.dataRequest?.respond(with: cachedResponse.data)
            loadingRequest.finishLoading()
            self.removeActiveRequest(identifier)
        }
    }

    private func fillContentInformation(
        _ contentInformationRequest: AVAssetResourceLoadingContentInformationRequest?,
        cachedResponse: ProgressiveMediaCacheResponse
    ) {
        guard let contentInformationRequest else { return }
        contentInformationRequest.isByteRangeAccessSupported = cachedResponse.isByteRangeAccessSupported
        contentInformationRequest.contentLength = cachedResponse.contentLength
        if let mimeType = cachedResponse.mimeType,
           let type = UTType(mimeType: mimeType) ?? UTType(mimeType: mimeType, conformingTo: .movie) {
            contentInformationRequest.contentType = type.identifier
        } else if let type = UTType(filenameExtension: "mp4") {
            contentInformationRequest.contentType = type.identifier
        }
    }

    private func contentLength(from response: HTTPURLResponse, dataLength: Int) -> Int64 {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let slashIndex = contentRange.lastIndex(of: "/"),
           let total = Int64(contentRange[contentRange.index(after: slashIndex)...]) {
            return total
        }
        if response.expectedContentLength > 0 {
            return response.expectedContentLength
        }
        return Int64(dataLength)
    }

    private func store(_ task: URLSessionDataTask, for identifier: ObjectIdentifier) -> Bool {
        lock.lock()
        guard activeRequests.contains(identifier) else {
            lock.unlock()
            return false
        }
        tasks[identifier] = task
        lock.unlock()
        return true
    }

    private func removeTask(for identifier: ObjectIdentifier) {
        lock.lock()
        tasks.removeValue(forKey: identifier)
        lock.unlock()
    }

    private func storeCacheLookupTask(_ task: Task<Void, Never>, for identifier: ObjectIdentifier) {
        lock.lock()
        cacheLookupTasks[identifier] = task
        lock.unlock()
    }

    private func removeCacheLookupTask(for identifier: ObjectIdentifier) {
        lock.lock()
        cacheLookupTasks.removeValue(forKey: identifier)
        lock.unlock()
    }

    private func storeActiveRequest(_ identifier: ObjectIdentifier) {
        lock.lock()
        activeRequests.insert(identifier)
        lock.unlock()
    }

    private func removeActiveRequest(_ identifier: ObjectIdentifier) {
        lock.lock()
        activeRequests.remove(identifier)
        lock.unlock()
    }

    private func isRequestActive(_ identifier: ObjectIdentifier) -> Bool {
        lock.lock()
        let isActive = activeRequests.contains(identifier)
        lock.unlock()
        return isActive
    }

    private static func error(code: Int = -1, message: String) -> NSError {
        NSError(
            domain: "cc.bili.progressive-resource-loader",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
