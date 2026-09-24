import Foundation
import Network
import QuartzCore

enum HLSRemoteRangeStreamer {
    struct HedgedStreamResult: Sendable {
        let sourceURL: URL
        let sourceIndex: Int
        let cachePayload: VideoRangeStreamCachePayload?
        let firstChunkElapsedMilliseconds: Double
    }

    nonisolated static func stream(
        range: HTTPByteRange,
        from url: URL,
        headers: [String: String],
        responseHeader: Data,
        connection: NWConnection,
        cacheLimit: Int64,
        startupChunkSize: Int = 32 * 1024,
        transform: HLSMediaSegmentTransform? = nil,
        onFirstChunkSent: (@Sendable (Int) async -> Void)? = nil
    ) async throws -> VideoRangeStreamCachePayload? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = range.length > 1_500_000 ? 3.2 : 2.0
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("bytes=\(range.start)-\(range.endInclusive)", forHTTPHeaderField: "Range")

        let stream = HLSRemoteRangeStreamingSession.shared.start(request: request)
        defer {
            HLSRemoteRangeStreamingSession.shared.finish(task: stream.task)
        }

        let response: URLResponse
        do {
            response = try await stream.handler.response()
        } catch let error as URLError {
            throw HLSBridgeRemoteFailure.urlSession(error, url: url, range: range)
        } catch {
            throw error
        }
        try HLSRemoteRangeResponseValidator.validate(response, requestedRange: range, url: url)

        let cacheCollector = VideoRangeStreamCacheCollector(range: range, cacheLimit: cacheLimit)
        var didStartResponse = false
        do {
            let chunkSize = min(max(startupChunkSize, 24 * 1024), 96 * 1024)
            var chunk = Data()
            var didNotifyFirstChunk = false
            var didApplyTransform = false
            chunk.reserveCapacity(chunkSize)
            for try await data in stream.handler.chunks {
                try Task.checkCancellation()
                try cacheCollector?.append(data)
                chunk.append(data)
                if chunk.count >= chunkSize {
                    let outboundChunk: Data?
                    if let transform, !didApplyTransform {
                        let transformResult = transform.applyResult(to: chunk)
                        if transformResult.didNormalizeTiming {
                            outboundChunk = transformResult.data
                            didApplyTransform = true
                        } else {
                            outboundChunk = nil
                        }
                    } else {
                        outboundChunk = chunk
                    }
                    if let outboundChunk {
                        if !didStartResponse {
                            try await send(responseHeader, to: connection)
                            didStartResponse = true
                        }
                        try await send(outboundChunk, to: connection)
                        if !didNotifyFirstChunk {
                            didNotifyFirstChunk = true
                            await onFirstChunkSent?(outboundChunk.count)
                        }
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
            }
            if !chunk.isEmpty {
                let outboundChunk: Data
                if let transform, !didApplyTransform {
                    let transformResult = transform.applyResult(to: chunk)
                    outboundChunk = transformResult.data
                    didApplyTransform = true
                } else {
                    outboundChunk = chunk
                }
                if !didStartResponse {
                    try await send(responseHeader, to: connection)
                    didStartResponse = true
                }
                try await send(outboundChunk, to: connection)
                if !didNotifyFirstChunk {
                    didNotifyFirstChunk = true
                    await onFirstChunkSent?(outboundChunk.count)
                }
            }
            guard didNotifyFirstChunk else {
                throw HLSBridgeRemoteFailure.emptyResponse(url: url, range: range)
            }
        } catch {
            stream.task.cancel()
            cacheCollector?.cancel()
            guard didStartResponse else { throw error }
            connection.cancel()
            throw HLSRangeStreamError.responseAlreadyStarted(error)
        }
        connection.cancel()
        return try cacheCollector?.finish()
    }

    nonisolated static func streamHedged(
        range: HTTPByteRange,
        from urls: [URL],
        headers: [String: String],
        responseHeader: Data,
        connection: NWConnection,
        cacheLimit: Int64,
        startupChunkSize: Int = 32 * 1024,
        transform: HLSMediaSegmentTransform? = nil,
        hedgeDelayNanoseconds: UInt64,
        onFirstChunkSent: (@Sendable (Int) async -> Void)? = nil
    ) async throws -> HedgedStreamResult {
        let sourceURLs = urls.removingDuplicates()
        guard let firstURL = sourceURLs.first else {
            throw PlayerEngineError.unsupportedMedia
        }
        guard sourceURLs.count > 1 else {
            let start = CACurrentMediaTime()
            let payload = try await stream(
                range: range,
                from: firstURL,
                headers: headers,
                responseHeader: responseHeader,
                connection: connection,
                cacheLimit: cacheLimit,
                startupChunkSize: startupChunkSize,
                transform: transform,
                onFirstChunkSent: onFirstChunkSent
            )
            return HedgedStreamResult(
                sourceURL: firstURL,
                sourceIndex: 0,
                cachePayload: payload,
                firstChunkElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: start)
            )
        }

        let result: Result<HLSRemoteRangePreparedCandidate, Error> = try await withThrowingTaskGroup(
            of: Result<HLSRemoteRangePreparedCandidate, Error>.self,
            returning: Result<HLSRemoteRangePreparedCandidate, Error>.self
        ) { group in
            for (index, url) in sourceURLs.enumerated() {
                group.addTask(priority: .userInitiated) {
                    do {
                        if index > 0 {
                            try await Task.sleep(
                                nanoseconds: hedgeDelayNanoseconds
                                    + UInt64(index - 1) * 40_000_000
                            )
                        }
                        let candidate = try await prepareCandidate(
                            range: range,
                            url: url,
                            sourceIndex: index,
                            headers: headers,
                            cacheLimit: cacheLimit,
                            startupChunkSize: startupChunkSize,
                            transform: transform
                        )
                        return .success(candidate)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var lastError: Error?
            while let candidateResult = try await group.next() {
                switch candidateResult {
                case let .success(candidate):
                    group.cancelAll()
                    do {
                        let payload = try await finishCandidate(
                            candidate,
                            responseHeader: responseHeader,
                            connection: connection,
                            onFirstChunkSent: onFirstChunkSent
                        )
                        candidate.finishedPayload = payload
                        return .success(candidate)
                    } catch {
                        lastError = error
                    }
                case let .failure(error):
                    lastError = error
                }
            }
            return .failure(lastError ?? PlayerEngineError.unsupportedMedia)
        }

        switch result {
        case let .success(candidate):
            return HedgedStreamResult(
                sourceURL: candidate.sourceURL,
                sourceIndex: candidate.sourceIndex,
                cachePayload: candidate.finishedPayload,
                firstChunkElapsedMilliseconds: candidate.firstChunkElapsedMilliseconds
            )
        case let .failure(error):
            throw error
        }
    }

    private nonisolated static func prepareCandidate(
        range: HTTPByteRange,
        url: URL,
        sourceIndex: Int,
        headers: [String: String],
        cacheLimit: Int64,
        startupChunkSize: Int,
        transform: HLSMediaSegmentTransform?
    ) async throws -> HLSRemoteRangePreparedCandidate {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = range.length > 1_500_000 ? 3.2 : 2.0
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("bytes=\(range.start)-\(range.endInclusive)", forHTTPHeaderField: "Range")

        let stream = HLSRemoteRangeStreamingSession.shared.start(request: request)
        let requestStart = CACurrentMediaTime()
        do {
            let response: URLResponse
            do {
                response = try await withTaskCancellationHandler {
                    try await stream.handler.response()
                } onCancel: {
                    stream.task.cancel()
                }
            } catch let error as URLError {
                throw HLSBridgeRemoteFailure.urlSession(error, url: url, range: range)
            }
            try HLSRemoteRangeResponseValidator.validate(response, requestedRange: range, url: url)

            let candidate = HLSRemoteRangePreparedCandidate(
                sourceURL: url,
                sourceIndex: sourceIndex,
                task: stream.task,
                handler: stream.handler,
                cacheCollector: VideoRangeStreamCacheCollector(range: range, cacheLimit: cacheLimit),
                range: range
            )
            try await candidate.prepareFirstChunk(
                startupChunkSize: startupChunkSize,
                transform: transform,
                startedAt: requestStart
            )
            return candidate
        } catch {
            stream.task.cancel()
            HLSRemoteRangeStreamingSession.shared.finish(task: stream.task)
            throw error
        }
    }

    private nonisolated static func finishCandidate(
        _ candidate: HLSRemoteRangePreparedCandidate,
        responseHeader: Data,
        connection: NWConnection,
        onFirstChunkSent: (@Sendable (Int) async -> Void)?
    ) async throws -> VideoRangeStreamCachePayload? {
        var didStartResponse = false
        do {
            try await send(responseHeader, to: connection)
            didStartResponse = true
            try await send(candidate.firstOutboundChunk, to: connection)
            await onFirstChunkSent?(candidate.firstOutboundChunk.count)

            var chunk = Data()
            let chunkSize = candidate.startupChunkSize
            chunk.reserveCapacity(chunkSize)
            while let data = try await candidate.nextChunk() {
                try Task.checkCancellation()
                try candidate.cacheCollector?.append(data)
                chunk.append(data)
                if chunk.count >= chunkSize {
                    let outboundChunk: Data?
                    if let transform = candidate.transform, !candidate.didApplyTransform {
                        let transformResult = transform.applyResult(to: chunk)
                        if transformResult.didNormalizeTiming {
                            outboundChunk = transformResult.data
                            candidate.didApplyTransform = true
                        } else {
                            outboundChunk = nil
                        }
                    } else {
                        outboundChunk = chunk
                    }
                    if let outboundChunk {
                        try await send(outboundChunk, to: connection)
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
            }

            if !chunk.isEmpty {
                let outboundChunk: Data
                if let transform = candidate.transform, !candidate.didApplyTransform {
                    outboundChunk = transform.applyResult(to: chunk).data
                    candidate.didApplyTransform = true
                } else {
                    outboundChunk = chunk
                }
                try await send(outboundChunk, to: connection)
            }
            connection.cancel()
            return try candidate.cacheCollector?.finish()
        } catch {
            candidate.task.cancel()
            candidate.cacheCollector?.cancel()
            if didStartResponse {
                connection.cancel()
                throw HLSRangeStreamError.responseAlreadyStarted(error)
            }
            throw error
        }
    }

    private nonisolated static func send(_ data: Data, to connection: NWConnection) async throws {
        guard !data.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

nonisolated private final class HLSRemoteRangePreparedCandidate: @unchecked Sendable {
    let sourceURL: URL
    let sourceIndex: Int
    let task: URLSessionDataTask
    let handler: HLSRemoteRangeStreamHandler
    let cacheCollector: VideoRangeStreamCacheCollector?
    let range: HTTPByteRange
    private(set) var startupChunkSize: Int
    private(set) var transform: HLSMediaSegmentTransform?
    private(set) var firstChunkElapsedMilliseconds: Double = 0
    private(set) var firstOutboundChunk = Data()

    private var iterator: AsyncThrowingStream<Data, Error>.Iterator
    var didApplyTransform: Bool
    var finishedPayload: VideoRangeStreamCachePayload?

    init(
        sourceURL: URL,
        sourceIndex: Int,
        task: URLSessionDataTask,
        handler: HLSRemoteRangeStreamHandler,
        cacheCollector: VideoRangeStreamCacheCollector?,
        range: HTTPByteRange,
        startupChunkSize: Int = 32 * 1024,
        transform: HLSMediaSegmentTransform? = nil
    ) {
        self.sourceURL = sourceURL
        self.sourceIndex = sourceIndex
        self.task = task
        self.handler = handler
        self.cacheCollector = cacheCollector
        self.range = range
        self.startupChunkSize = min(max(startupChunkSize, 24 * 1024), 96 * 1024)
        self.transform = transform
        self.iterator = handler.chunks.makeAsyncIterator()
        self.didApplyTransform = false
    }

    func prepareFirstChunk(
        startupChunkSize: Int,
        transform: HLSMediaSegmentTransform?,
        startedAt: CFTimeInterval
    ) async throws {
        self.startupChunkSize = min(max(startupChunkSize, 24 * 1024), 96 * 1024)
        self.transform = transform
        var chunk = Data()
        chunk.reserveCapacity(self.startupChunkSize)
        while let data = try await iterator.next() {
            try Task.checkCancellation()
            try cacheCollector?.append(data)
            chunk.append(data)
            guard chunk.count >= self.startupChunkSize else { continue }

            if let transform, !didApplyTransform {
                let transformResult = transform.applyResult(to: chunk)
                guard transformResult.didNormalizeTiming else { continue }
                firstOutboundChunk = transformResult.data
                didApplyTransform = true
            } else {
                firstOutboundChunk = chunk
            }
            firstChunkElapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: startedAt)
            return
        }

        guard !chunk.isEmpty else {
            throw HLSBridgeRemoteFailure.emptyResponse(url: sourceURL, range: range)
        }
        if let transform, !didApplyTransform {
            firstOutboundChunk = transform.applyResult(to: chunk).data
            didApplyTransform = true
        } else {
            firstOutboundChunk = chunk
        }
        firstChunkElapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: startedAt)
    }

    func nextChunk() async throws -> Data? {
        try await iterator.next()
    }

    deinit {
        task.cancel()
        HLSRemoteRangeStreamingSession.shared.finish(task: task)
        cacheCollector?.cancel()
    }
}

nonisolated enum PlaybackRangeStreamingSessionCoordinator {
    static func refreshForNetworkPathChange() {
        HLSRemoteRangeStreamingSession.shared.refreshForNetworkPathChange()
    }
}

nonisolated private final class HLSRemoteRangeStreamingSession: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = HLSRemoteRangeStreamingSession()

    private let lock = NSLock()
    private let delegateQueue: OperationQueue
    private var session: URLSession!
    private var handlers: [ObjectIdentifier: HLSRemoteRangeStreamHandler] = [:]

    private override init() {
        delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 2
        delegateQueue.qualityOfService = .userInitiated
        super.init()
        session = URLSession(
            configuration: BiliURLSessionFactory.makePlaybackStreamingConfiguration(),
            delegate: self,
            delegateQueue: delegateQueue
        )
    }

    func start(request: URLRequest) -> (task: URLSessionDataTask, handler: HLSRemoteRangeStreamHandler) {
        let handler = HLSRemoteRangeStreamHandler()
        lock.lock()
        let currentSession = session!
        let task = currentSession.dataTask(with: request)
        handlers[ObjectIdentifier(task)] = handler
        lock.unlock()
        task.resume()
        return (task, handler)
    }

    func finish(task: URLSessionTask) {
        lock.lock()
        handlers[ObjectIdentifier(task)] = nil
        lock.unlock()
    }

    func refreshForNetworkPathChange() {
        let oldSession: URLSession
        lock.lock()
        oldSession = session
        session = URLSession(
            configuration: BiliURLSessionFactory.makePlaybackStreamingConfiguration(),
            delegate: self,
            delegateQueue: delegateQueue
        )
        lock.unlock()
        oldSession.finishTasksAndInvalidate()
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let handler = handler(for: dataTask) else {
            completionHandler(.cancel)
            return
        }
        handler.receive(response: response)
        completionHandler(.allow)
    }

    func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        handler(for: dataTask)?.receive(data: data)
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        handler(for: task)?.complete(error: error)
        finish(task: task)
    }

    private func handler(for task: URLSessionTask) -> HLSRemoteRangeStreamHandler? {
        lock.lock()
        let handler = handlers[ObjectIdentifier(task)]
        lock.unlock()
        return handler
    }
}

nonisolated private final class HLSRemoteRangeStreamHandler: @unchecked Sendable {
    let chunks: AsyncThrowingStream<Data, Error>

    private let lock = NSLock()
    private let chunkContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private var responseContinuation: CheckedContinuation<URLResponse, Error>?
    private var responseResult: Result<URLResponse, Error>?

    init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation?
        self.chunks = AsyncThrowingStream(Data.self, bufferingPolicy: .unbounded) { streamContinuation in
            continuation = streamContinuation
        }
        self.chunkContinuation = continuation!
    }

    func response() async throws -> URLResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let responseResult {
                lock.unlock()
                continuation.resume(with: responseResult)
                return
            }
            responseContinuation = continuation
            lock.unlock()
        }
    }

    func receive(response: URLResponse) {
        completeResponse(.success(response))
    }

    func receive(data: Data) {
        chunkContinuation.yield(data)
    }

    func complete(error: Error?) {
        if let error {
            completeResponse(.failure(error))
            chunkContinuation.finish(throwing: error)
        } else {
            completeResponse(.failure(PlayerEngineError.unsupportedMedia))
            chunkContinuation.finish()
        }
    }

    private func completeResponse(_ result: Result<URLResponse, Error>) {
        lock.lock()
        guard responseResult == nil else {
            lock.unlock()
            return
        }
        responseResult = result
        let continuation = responseContinuation
        responseContinuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

enum VideoRangeStreamCachePayload: Sendable {
    case data(Data)
    case file(URL)

    nonisolated var byteCount: Int {
        switch self {
        case let .data(data):
            return data.count
        case let .file(url):
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size
        }
    }

    nonisolated func loadData() throws -> Data {
        switch self {
        case let .data(data):
            return data
        case let .file(url):
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }
    }

    nonisolated func cleanup() {
        if case let .file(url) = self {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

nonisolated final class VideoRangeStreamCacheCollector: @unchecked Sendable {
    private let fileURL: URL?
    private var data: Data?
    private var handle: FileHandle?
    private var isFinished = false

    init?(range: HTTPByteRange, cacheLimit: Int64) {
        guard range.length <= cacheLimit else { return nil }
        if range.length > 1_500_000 {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("cc.bili.hls-stream-cache", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let candidateURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("tmp")
            FileManager.default.createFile(atPath: candidateURL.path, contents: nil)
            if let handle = try? FileHandle(forWritingTo: candidateURL) {
                self.fileURL = candidateURL
                self.handle = handle
                self.data = nil
            } else {
                self.fileURL = nil
                self.handle = nil
                self.data = Data()
            }
        } else {
            self.fileURL = nil
            self.handle = nil
            self.data = Data()
            self.data?.reserveCapacity(Int(range.length))
        }
    }

    func append(_ chunk: Data) throws {
        if let handle {
            try handle.write(contentsOf: chunk)
        } else {
            data?.append(chunk)
        }
    }

    func finish() throws -> VideoRangeStreamCachePayload? {
        guard !isFinished else { return nil }
        isFinished = true
        if let handle {
            try handle.close()
            self.handle = nil
        }
        if let fileURL {
            return .file(fileURL)
        }
        if let data {
            return .data(data)
        }
        return nil
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        try? handle?.close()
        handle = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        data = nil
    }

    deinit {
        cancel()
    }
}
