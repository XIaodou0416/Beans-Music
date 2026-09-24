import Compression
import CryptoKit
import Foundation
import Network
import OSLog

nonisolated enum LiveDanmakuDiagnosticPhase: Equatable, Sendable {
    case idle
    case fetchingConfig
    case connecting
    case authenticating
    case waitingForPackets
    case receiving
    case rendering
    case reconnecting
    case stopped
    case failed

    var title: String {
        switch self {
        case .idle:
            return "待启动"
        case .fetchingConfig:
            return "取配置"
        case .connecting:
            return "连接中"
        case .authenticating:
            return "鉴权中"
        case .waitingForPackets:
            return "等收包"
        case .receiving:
            return "接收中"
        case .rendering:
            return "已渲染"
        case .reconnecting:
            return "重连中"
        case .stopped:
            return "已停止"
        case .failed:
            return "异常"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "pause.circle"
        case .fetchingConfig:
            return "arrow.down.circle"
        case .connecting:
            return "network"
        case .authenticating:
            return "key.horizontal"
        case .waitingForPackets:
            return "clock"
        case .receiving:
            return "waveform.path.ecg"
        case .rendering:
            return "checkmark.circle.fill"
        case .reconnecting:
            return "arrow.clockwise"
        case .stopped:
            return "stop.circle"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

nonisolated enum LiveDanmakuDiagnosticEvent: Sendable {
    case serviceStarted(roomID: Int)
    case historyLoaded(count: Int)
    case historyFailed(error: String)
    case contextReady(uid: Int, hasCookie: Bool, hasBuvid: Bool)
    case configRequestStarted
    case configLoaded(hostCount: Int, hasToken: Bool, selectedEndpoint: String?)
    case endpointAttempt(index: Int, total: Int, endpoint: String)
    case endpointFailed(endpoint: String, error: String)
    case webSocketResumed(endpoint: String)
    case authSent(hasToken: Bool)
    case heartbeatStarted
    case heartbeatSent
    case messageReceived(byteCount: Int)
    case packetReceived(operation: Int, version: Int, bodyBytes: Int)
    case authReply
    case heartbeatReply
    case commandPacket(version: Int, bodyBytes: Int)
    case commandReceived(name: String)
    case danmakuParsed(text: String)
    case itemsDelivered(count: Int)
    case inflateSucceeded(version: Int, byteCount: Int)
    case inflateFailed(version: Int)
    case jsonParseFailed(byteCount: Int)
    case reconnectScheduled(error: String)
    case stopped
    case renderState(isDanmakuEnabled: Bool, overlayItemCount: Int, hasPresentedPlayback: Bool)
}

nonisolated struct LiveDanmakuDiagnosticSnapshot: Equatable, Sendable {
    var roomID: Int
    var phase: LiveDanmakuDiagnosticPhase
    var startedAt: Date
    var updatedAt: Date
    var uid: Int
    var hasCookie: Bool
    var hasBuvid: Bool
    var historyMessageCount: Int?
    var historyError: String?
    var hostCount: Int
    var hasToken: Bool
    var selectedEndpoint: String?
    var endpointAttemptCount: Int
    var endpointFailureCount: Int
    var lastEndpointError: String?
    var heartbeatSentCount: Int
    var heartbeatReplyCount: Int
    var rawMessageCount: Int
    var rawBytesReceived: Int
    var packetCount: Int
    var authReplyCount: Int
    var commandPacketCount: Int
    var commandCount: Int
    var danmakuCommandCount: Int
    var parsedItemCount: Int
    var deliveredItemCount: Int
    var overlayItemCount: Int
    var inflateSuccessCount: Int
    var inflateFailureCount: Int
    var jsonParseFailureCount: Int
    var reconnectCount: Int
    var isDanmakuEnabled: Bool
    var hasPresentedPlayback: Bool
    var lastCommandName: String?
    var lastDanmakuText: String?
    var lastError: String?
    var lastPacketAt: Date?
    var lastHeartbeatReplyAt: Date?
    var lastDeliveredAt: Date?

    init(roomID: Int) {
        let now = Date()
        self.roomID = roomID
        self.phase = .idle
        self.startedAt = now
        self.updatedAt = now
        self.uid = 0
        self.hasCookie = false
        self.hasBuvid = false
        self.historyMessageCount = nil
        self.historyError = nil
        self.hostCount = 0
        self.hasToken = false
        self.selectedEndpoint = nil
        self.endpointAttemptCount = 0
        self.endpointFailureCount = 0
        self.lastEndpointError = nil
        self.heartbeatSentCount = 0
        self.heartbeatReplyCount = 0
        self.rawMessageCount = 0
        self.rawBytesReceived = 0
        self.packetCount = 0
        self.authReplyCount = 0
        self.commandPacketCount = 0
        self.commandCount = 0
        self.danmakuCommandCount = 0
        self.parsedItemCount = 0
        self.deliveredItemCount = 0
        self.overlayItemCount = 0
        self.inflateSuccessCount = 0
        self.inflateFailureCount = 0
        self.jsonParseFailureCount = 0
        self.reconnectCount = 0
        self.isDanmakuEnabled = true
        self.hasPresentedPlayback = false
        self.lastCommandName = nil
        self.lastDanmakuText = nil
        self.lastError = nil
        self.lastPacketAt = nil
        self.lastHeartbeatReplyAt = nil
        self.lastDeliveredAt = nil
    }

    var selectedEndpointHost: String {
        guard let selectedEndpoint, !selectedEndpoint.isEmpty else { return "-" }
        return URL(string: selectedEndpoint)?.host ?? selectedEndpoint
    }

    var configSummary: String {
        if hostCount > 0 || selectedEndpoint != nil {
            let hostText = hostCount > 0 ? "\(hostCount) 节点" : "默认节点"
            return "\(hostText) · \(hasToken ? "有 token" : "无 token")"
        }
        if phase == .fetchingConfig {
            return "请求中"
        }
        return "未获取"
    }

    var historySummary: String {
        if let historyMessageCount {
            return "\(historyMessageCount) 条"
        }
        if historyError != nil {
            return "加载失败"
        }
        return "加载中"
    }

    var connectionSummary: String {
        if phase == .connecting || phase == .authenticating || phase == .waitingForPackets || rawMessageCount > 0 {
            return selectedEndpointHost
        }
        if phase == .reconnecting {
            return "等待重连"
        }
        return "-"
    }

    var receiveSummary: String {
        "\(rawMessageCount) 消息 · \(packetCount) 包"
    }

    var commandSummary: String {
        "\(commandCount) 命令 · \(danmakuCommandCount) 弹幕"
    }

    var endpointSummary: String {
        "\(endpointAttemptCount) 尝试 · \(endpointFailureCount) 失败"
    }

    var renderSummary: String {
        guard isDanmakuEnabled else { return "弹幕关闭" }
        if deliveredItemCount > 0 || overlayItemCount > 0 {
            return "\(overlayItemCount) 条在覆盖层"
        }
        return "未收到可渲染弹幕"
    }

    var conclusion: String {
        if !isDanmakuEnabled {
            return "弹幕开关已关闭，覆盖层不会渲染。"
        }
        if let historyMessageCount, historyMessageCount > 0, rawMessageCount == 0 {
            return "已回填 \(historyMessageCount) 条近期弹幕，实时连接仍在等待新消息。"
        }
        if let historyError, rawMessageCount == 0 {
            return "近期弹幕未能回填：\(historyError)"
        }
        if phase == .failed, let lastError {
            return "弹幕链路异常：\(lastError)"
        }
        if phase == .fetchingConfig || (hostCount == 0 && rawMessageCount == 0) {
            return "正在获取直播弹幕配置。"
        }
        if phase == .connecting || phase == .authenticating {
            return "已拿到配置，正在建立弹幕 WebSocket。"
        }
        if rawMessageCount == 0 {
            if reconnectCount > 0, let lastError {
                return "WebSocket 暂无回包，正在重连：\(lastError)"
            }
            return "WebSocket 已启动，正在等待服务端回包。"
        }
        if deliveredItemCount > 0 && overlayItemCount == 0 {
            return "弹幕已交给 UI，但覆盖层列表为空。"
        }
        if deliveredItemCount > 0 && !hasPresentedPlayback {
            return "弹幕链路正常，播放器首帧未完成时可能暂时看不到。"
        }
        if deliveredItemCount > 0 {
            return "直播弹幕链路正常。"
        }
        if danmakuCommandCount > 0 {
            return "已经解析到弹幕，但还没有交给 UI 覆盖层。"
        }
        if commandCount > 0 && danmakuCommandCount == 0 {
            if let lastCommandName {
                return "收到直播命令，但暂时没有可渲染文本；最后命令 \(lastCommandName)。"
            }
            return "收到直播命令，但暂时没有可渲染文本。"
        }
        if inflateFailureCount > 0 && commandCount == 0 {
            return "收到命令包但解压失败，优先检查压缩协议。"
        }
        if jsonParseFailureCount > 0 && commandCount == 0 {
            return "收到命令包但 JSON 解析失败，优先检查消息格式。"
        }
        if packetCount > 0 && commandPacketCount == 0 {
            return "连接正常，目前只收到心跳/系统包。"
        }
        if authReplyCount == 0 {
            return "已经收到服务端数据，但还没有识别到鉴权回包。"
        }
        return "链路已建立，正在等待直播间弹幕。"
    }

    mutating func apply(_ event: LiveDanmakuDiagnosticEvent) {
        let now = Date()
        updatedAt = now
        switch event {
        case .serviceStarted(let roomID):
            self = LiveDanmakuDiagnosticSnapshot(roomID: roomID)
            phase = .fetchingConfig
            startedAt = now
            updatedAt = now
        case .historyLoaded(let count):
            historyMessageCount = max(0, count)
            historyError = nil
        case .historyFailed(let error):
            historyMessageCount = nil
            historyError = error
        case .contextReady(let uid, let hasCookie, let hasBuvid):
            self.uid = uid
            self.hasCookie = hasCookie
            self.hasBuvid = hasBuvid
        case .configRequestStarted:
            phase = .fetchingConfig
            lastError = nil
        case .configLoaded(let hostCount, let hasToken, let selectedEndpoint):
            self.hostCount = hostCount
            self.hasToken = hasToken
            self.selectedEndpoint = selectedEndpoint
            phase = .connecting
            lastError = nil
        case .endpointAttempt(_, _, let endpoint):
            endpointAttemptCount += 1
            selectedEndpoint = endpoint
            phase = .connecting
        case .endpointFailed(let endpoint, let error):
            endpointFailureCount += 1
            selectedEndpoint = endpoint
            lastEndpointError = "\(URL(string: endpoint)?.host ?? endpoint)：\(error)"
        case .webSocketResumed(let endpoint):
            selectedEndpoint = endpoint
            phase = .authenticating
        case .authSent(let hasToken):
            self.hasToken = hasToken
            phase = .authenticating
        case .heartbeatStarted:
            phase = .waitingForPackets
        case .heartbeatSent:
            heartbeatSentCount += 1
        case .messageReceived(let byteCount):
            rawMessageCount += 1
            rawBytesReceived += byteCount
            lastPacketAt = now
            if phase != .rendering {
                phase = .receiving
            }
        case .packetReceived:
            packetCount += 1
            lastPacketAt = now
        case .authReply:
            authReplyCount += 1
            if phase != .rendering {
                phase = .waitingForPackets
            }
        case .heartbeatReply:
            heartbeatReplyCount += 1
            lastHeartbeatReplyAt = now
        case .commandPacket:
            commandPacketCount += 1
        case .commandReceived(let name):
            commandCount += 1
            lastCommandName = name
        case .danmakuParsed(let text):
            danmakuCommandCount += 1
            parsedItemCount += 1
            lastDanmakuText = text
        case .itemsDelivered(let count):
            deliveredItemCount += count
            lastDeliveredAt = now
            phase = .rendering
        case .inflateSucceeded:
            inflateSuccessCount += 1
        case .inflateFailed:
            inflateFailureCount += 1
        case .jsonParseFailed:
            jsonParseFailureCount += 1
        case .reconnectScheduled(let error):
            reconnectCount += 1
            lastError = error
            phase = .reconnecting
        case .stopped:
            phase = .stopped
        case .renderState(let isDanmakuEnabled, let overlayItemCount, let hasPresentedPlayback):
            self.isDanmakuEnabled = isDanmakuEnabled
            self.overlayItemCount = overlayItemCount
            self.hasPresentedPlayback = hasPresentedPlayback
        }
    }
}

private enum LiveDanmakuWebSocketOpenError: LocalizedError, Sendable {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let reason):
            return reason
        }
    }
}

private actor LiveDanmakuNetworkWebSocketOpenGate {
    private var isReady = false
    private var terminalFailure: String?
    private var isCancelled = false
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForReady() async throws {
        if isCancelled {
            throw CancellationError()
        }
        if let terminalFailure {
            throw LiveDanmakuWebSocketOpenError.failed(terminalFailure)
        }
        if isReady {
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func ready() {
        guard !isCancelled, terminalFailure == nil else { return }
        isReady = true
        continuation?.resume()
        continuation = nil
    }

    func failed(_ reason: String) {
        guard !isCancelled else { return }
        terminalFailure = reason
        continuation?.resume(throwing: LiveDanmakuWebSocketOpenError.failed(reason))
        continuation = nil
    }

    func cancel() {
        isCancelled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    func failureReason() -> String? {
        terminalFailure
    }
}

private nonisolated final class LiveDanmakuNetworkWebSocket: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let openGate = LiveDanmakuNetworkWebSocketOpenGate()

    init(endpoint: URL, headers: [String: String]) {
        let webSocketOptions = NWProtocolWebSocket.Options()
        webSocketOptions.autoReplyPing = true
        webSocketOptions.maximumMessageSize = 2 * 1024 * 1024
        webSocketOptions.setAdditionalHeaders(
            headers
                .filter { !$0.value.isEmpty }
                .map { (name: $0.key, value: $0.value) }
        )

        let parameters = NWParameters(
            tls: NWProtocolTLS.Options(),
            tcp: NWProtocolTCP.Options()
        )
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

        let connection = NWConnection(to: .url(endpoint), using: parameters)
        self.connection = connection
        self.queue = DispatchQueue(label: "cc.bili.live-danmaku.network-websocket")
        connection.stateUpdateHandler = { [openGate] state in
            switch state {
            case .ready:
                Task {
                    await openGate.ready()
                }
            case .failed(let error):
                let reason = error.localizedDescription
                Task {
                    await openGate.failed(reason)
                }
            case .cancelled:
                Task {
                    await openGate.failed("系统网络连接已取消")
                }
            default:
                break
            }
        }
    }

    deinit {
        connection.cancel()
    }

    func open() async throws {
        connection.start(queue: queue)
        try await withTaskCancellationHandler {
            try await openGate.waitForReady()
        } onCancel: { [connection, openGate] in
            connection.cancel()
            Task {
                await openGate.cancel()
            }
        }
    }

    func send(_ data: Data) async throws {
        let context = NWConnection.ContentContext(
            identifier: "bili-live-binary",
            metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)]
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    func receive() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receiveMessage { data, _, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(
                            throwing: LiveDanmakuWebSocketOpenError.failed(
                                "系统网络连接未返回可读取的数据"
                            )
                        )
                    }
                }
            }
        } onCancel: { [connection] in
            connection.cancel()
        }
    }

    func cancel() {
        connection.cancel()
        Task { [openGate] in
            await openGate.cancel()
        }
    }

    func terminalFailure() async -> String? {
        await openGate.failureReason()
    }
}

private enum LiveDanmakuRawWebSocketError: LocalizedError, Sendable {
    case handshakeRejected(status: String, detail: String)
    case invalidHandshake(detail: String)
    case protocolViolation(String)
    case closed(code: Int?, reason: String?)
    case transportClosed

    var errorDescription: String? {
        switch self {
        case .handshakeRejected(let status, let detail):
            return "原始握手被服务端拒绝（\(status)）：\(detail)"
        case .invalidHandshake(let detail):
            return "原始握手响应无效：\(detail)"
        case .protocolViolation(let detail):
            return "原始 WebSocket 协议异常：\(detail)"
        case .closed(let code, let reason):
            let codeText = code.map(String.init) ?? "未提供"
            let reasonText = reason?.isEmpty == false ? reason! : "未提供原因"
            return "服务端关闭 WebSocket（code \(codeText)）：\(reasonText)"
        case .transportClosed:
            return "原始 WebSocket 传输已关闭"
        }
    }
}

private struct LiveDanmakuRawWebSocketFrame: Sendable {
    let isFinal: Bool
    let opcode: UInt8
    let payload: Data
}

private enum LiveDanmakuRawWebSocketMessageEvent: Sendable {
    case data(Data)
    case ping(Data)
    case closed(code: Int?, reason: String?)
    case ignore
}

private actor LiveDanmakuRawWebSocketReceiveBuffer {
    private var buffer = Data()

    func append(_ data: Data) {
        buffer.append(data)
    }

    func takeHandshakeResponse() -> Data? {
        let delimiter = Data([13, 10, 13, 10])
        guard let range = buffer.range(of: delimiter) else { return nil }
        let response = Data(buffer[..<range.upperBound])
        buffer.removeSubrange(..<range.upperBound)
        return response
    }

    func takeFrame() -> LiveDanmakuRawWebSocketFrame? {
        let bytes = [UInt8](buffer)
        guard bytes.count >= 2 else { return nil }

        let isFinal = (bytes[0] & 0x80) != 0
        let opcode = bytes[0] & 0x0F
        let isMasked = (bytes[1] & 0x80) != 0
        let lengthMarker = Int(bytes[1] & 0x7F)
        var offset = 2
        let payloadLength: Int

        switch lengthMarker {
        case 0...125:
            payloadLength = lengthMarker
        case 126:
            guard bytes.count >= offset + 2 else { return nil }
            payloadLength = Int(bytes.bigEndianUInt16(at: offset))
            offset += 2
        case 127:
            guard bytes.count >= offset + 8 else { return nil }
            let value = bytes.bigEndianUInt64(at: offset)
            guard value <= UInt64(Int.max) else {
                return nil
            }
            payloadLength = Int(value)
            offset += 8
        default:
            return nil
        }

        let maskingKey: [UInt8]
        if isMasked {
            guard bytes.count >= offset + 4 else { return nil }
            maskingKey = Array(bytes[offset..<(offset + 4)])
            offset += 4
        } else {
            maskingKey = []
        }

        guard payloadLength <= 2 * 1024 * 1024,
              bytes.count >= offset + payloadLength
        else { return nil }

        var payload = Data(bytes[offset..<(offset + payloadLength)])
        if !maskingKey.isEmpty {
            payload = Data(payload.enumerated().map { index, byte in
                byte ^ maskingKey[index % maskingKey.count]
            })
        }
        buffer.removeSubrange(..<(offset + payloadLength))
        return LiveDanmakuRawWebSocketFrame(isFinal: isFinal, opcode: opcode, payload: payload)
    }
}

private actor LiveDanmakuRawWebSocketMessageAccumulator {
    private var fragmentedOpcode: UInt8?
    private var fragmentedPayload = Data()

    func process(_ frame: LiveDanmakuRawWebSocketFrame) -> LiveDanmakuRawWebSocketMessageEvent {
        switch frame.opcode {
        case 0x8:
            let closeCode: Int?
            let reason: String?
            if frame.payload.count >= 2 {
                let bytes = [UInt8](frame.payload)
                closeCode = Int((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
                reason = frame.payload.count > 2
                    ? String(data: frame.payload.dropFirst(2), encoding: .utf8)
                    : nil
            } else {
                closeCode = nil
                reason = nil
            }
            return .closed(code: closeCode, reason: reason)
        case 0x9:
            return .ping(frame.payload)
        case 0xA:
            return .ignore
        case 0x0:
            guard fragmentedOpcode != nil else {
                return .ignore
            }
            fragmentedPayload.append(frame.payload)
            guard frame.isFinal else { return .ignore }
            let completed = fragmentedPayload
            fragmentedOpcode = nil
            fragmentedPayload.removeAll(keepingCapacity: true)
            return .data(completed)
        case 0x1, 0x2:
            guard fragmentedOpcode == nil else {
                return .ignore
            }
            guard !frame.isFinal else { return .data(frame.payload) }
            fragmentedOpcode = frame.opcode
            fragmentedPayload = frame.payload
            return .ignore
        default:
            return .ignore
        }
    }
}

nonisolated final class LiveDanmakuRawWebSocket: @unchecked Sendable {
    private let endpoint: URL
    private let headers: [String: String]
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let openGate = LiveDanmakuNetworkWebSocketOpenGate()
    private let receiveBuffer = LiveDanmakuRawWebSocketReceiveBuffer()
    private let messageAccumulator = LiveDanmakuRawWebSocketMessageAccumulator()

    init(endpoint: URL, headers: [String: String]) {
        self.endpoint = endpoint
        self.headers = headers

        let host = endpoint.host ?? "broadcastlv.chat.bilibili.com"
        let portValue = UInt16(clamping: endpoint.port ?? 443)
        let port = NWEndpoint.Port(rawValue: portValue) ?? .https
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, host)
        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        self.connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        self.queue = DispatchQueue(label: "cc.bili.live-danmaku.raw-websocket")

        connection.stateUpdateHandler = { [openGate] state in
            switch state {
            case .ready:
                Task {
                    await openGate.ready()
                }
            case .failed(let error):
                Task {
                    await openGate.failed(error.localizedDescription)
                }
            case .cancelled:
                Task {
                    await openGate.failed("原始 WebSocket 连接已取消")
                }
            default:
                break
            }
        }
    }

    deinit {
        connection.cancel()
    }

    func open() async throws {
        connection.start(queue: queue)
        try await withTaskCancellationHandler {
            try await openGate.waitForReady()
            let key = Self.makeWebSocketKey()
            try await sendRaw(Self.rawUpgradeRequest(endpoint: endpoint, headers: headers, key: key))

            while let response = await receiveBuffer.takeHandshakeResponse() {
                try Self.validateHandshakeResponse(response, expectedKey: key)
                return
            }
            while true {
                let chunk = try await receiveChunk()
                await receiveBuffer.append(chunk)
                if let response = await receiveBuffer.takeHandshakeResponse() {
                    try Self.validateHandshakeResponse(response, expectedKey: key)
                    return
                }
            }
        } onCancel: { [connection, openGate] in
            connection.cancel()
            Task {
                await openGate.cancel()
            }
        }
    }

    func send(_ data: Data) async throws {
        try await sendFrame(opcode: 0x2, payload: data)
    }

    func receive() async throws -> Data {
        while true {
            if let frame = await receiveBuffer.takeFrame() {
                switch await messageAccumulator.process(frame) {
                case .data(let data):
                    return data
                case .ping(let payload):
                    try await sendFrame(opcode: 0xA, payload: payload)
                case .closed(let code, let reason):
                    throw LiveDanmakuRawWebSocketError.closed(code: code, reason: reason)
                case .ignore:
                    break
                }
                continue
            }

            let chunk = try await receiveChunk()
            await receiveBuffer.append(chunk)
        }
    }

    func cancel() {
        connection.cancel()
        Task { [openGate] in
            await openGate.cancel()
        }
    }

    func terminalFailure() async -> String? {
        await openGate.failureReason()
    }

    private func sendRaw(_ data: Data) async throws {
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

    private func receiveChunk() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                    content,
                    _,
                    isComplete,
                    error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let content, !content.isEmpty {
                        continuation.resume(returning: content)
                    } else if isComplete {
                        continuation.resume(throwing: LiveDanmakuRawWebSocketError.transportClosed)
                    } else {
                        continuation.resume(
                            throwing: LiveDanmakuRawWebSocketError.protocolViolation(
                                "传输层返回空数据"
                            )
                        )
                    }
                }
            }
        } onCancel: { [connection] in
            connection.cancel()
        }
    }

    private func sendFrame(opcode: UInt8, payload: Data) async throws {
        guard payload.count <= 2 * 1024 * 1024 else {
            throw LiveDanmakuRawWebSocketError.protocolViolation("待发送帧过大")
        }

        let maskingKey = Data((0..<4).map { _ in UInt8.random(in: .min ... .max) })
        let frame = Self.makeClientFrame(opcode: opcode, payload: payload, maskingKey: maskingKey)
        try await sendRaw(frame)
    }

    private static func makeWebSocketKey() -> String {
        Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()
    }

    static func rawUpgradeRequest(endpoint: URL, headers: [String: String], key: String) -> Data {
        let host = endpoint.host ?? "broadcastlv.chat.bilibili.com"
        let authority: String
        if let port = endpoint.port, port != 443 {
            authority = "\(host):\(port)"
        } else {
            authority = host
        }
        let path = endpoint.path.isEmpty ? "/sub" : endpoint.path
        let target: String
        if let query = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
           !query.isEmpty {
            target = "\(path)?\(query)"
        } else {
            target = path
        }

        let reservedHeaderNames: Set<String> = [
            "host",
            "connection",
            "upgrade",
            "sec-websocket-key",
            "sec-websocket-version"
        ]
        var lines = [
            "GET \(target) HTTP/1.1",
            "Host: \(authority)",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(key)",
            "Sec-WebSocket-Version: 13"
        ]
        for (name, value) in headers.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
            guard !reservedHeaderNames.contains(name.lowercased()) else { continue }
            let sanitizedName = name.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            let sanitizedValue = value.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            guard !sanitizedName.isEmpty, !sanitizedValue.isEmpty else { continue }
            lines.append("\(sanitizedName): \(sanitizedValue)")
        }
        lines.append("")
        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    static func validateHandshakeResponse(_ response: Data, expectedKey: String) throws {
        guard let text = String(data: response, encoding: .utf8) else {
            throw LiveDanmakuRawWebSocketError.invalidHandshake(detail: "响应不是 UTF-8 文本")
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else {
            throw LiveDanmakuRawWebSocketError.invalidHandshake(detail: "缺少 HTTP 状态行")
        }
        var headerValues = [String: String]()
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, headerValues[name] == nil else { continue }
            headerValues[name] = value
        }

        guard statusLine.contains(" 101 ") || statusLine.hasSuffix(" 101") else {
            let detail = lines.dropFirst().first(where: { !$0.isEmpty }) ?? "未提供详情"
            throw LiveDanmakuRawWebSocketError.handshakeRejected(status: statusLine, detail: detail)
        }
        guard headerValues["upgrade"]?.lowercased() == "websocket" else {
            throw LiveDanmakuRawWebSocketError.invalidHandshake(detail: "缺少 Upgrade: websocket")
        }
        let expectedAccept = Data(
            Insecure.SHA1.hash(data: Data("\(expectedKey)258EAFA5-E914-47DA-95CA-C5AB0DC85B11".utf8))
        ).base64EncodedString()
        guard headerValues["sec-websocket-accept"] == expectedAccept else {
            throw LiveDanmakuRawWebSocketError.invalidHandshake(detail: "Sec-WebSocket-Accept 校验失败")
        }
    }

    private static func makeClientFrame(opcode: UInt8, payload: Data, maskingKey: Data) -> Data {
        var frame = Data([0x80 | (opcode & 0x0F)])
        switch payload.count {
        case 0...125:
            frame.append(0x80 | UInt8(payload.count))
        case 126...Int(UInt16.max):
            frame.append(0x80 | 126)
            frame.appendBigEndianUInt16(UInt16(payload.count))
        default:
            frame.append(0x80 | 127)
            frame.appendBigEndianUInt64(UInt64(payload.count))
        }
        frame.append(maskingKey)
        let mask = [UInt8](maskingKey)
        frame.append(contentsOf: payload.enumerated().map { index, byte in
            byte ^ mask[index % mask.count]
        })
        return frame
    }
}

private actor LiveDanmakuWebSocketOpenGate {
    private var openedTaskIDs = Set<Int>()
    private var didOpenTaskIDs = Set<Int>()
    private var cancelledTaskIDs = Set<Int>()
    private var failures = [Int: String]()
    private var terminalFailures = [Int: String]()
    private var continuations = [Int: CheckedContinuation<Void, Error>]()

    func waitForOpen(taskID: Int) async throws {
        if cancelledTaskIDs.remove(taskID) != nil {
            throw CancellationError()
        }
        if let failure = failures.removeValue(forKey: taskID) {
            throw LiveDanmakuWebSocketOpenError.failed(failure)
        }
        if openedTaskIDs.remove(taskID) != nil {
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            continuations[taskID] = continuation
        }
    }

    func opened(taskID: Int) {
        guard !cancelledTaskIDs.contains(taskID), failures[taskID] == nil else { return }
        didOpenTaskIDs.insert(taskID)
        if let continuation = continuations.removeValue(forKey: taskID) {
            continuation.resume()
        } else {
            openedTaskIDs.insert(taskID)
        }
    }

    func failed(taskID: Int, reason: String) {
        guard !cancelledTaskIDs.contains(taskID) else { return }
        openedTaskIDs.remove(taskID)
        terminalFailures[taskID] = reason
        if let continuation = continuations.removeValue(forKey: taskID) {
            continuation.resume(throwing: LiveDanmakuWebSocketOpenError.failed(reason))
        } else {
            failures[taskID] = reason
        }
    }

    func cancel(taskID: Int) {
        openedTaskIDs.remove(taskID)
        didOpenTaskIDs.remove(taskID)
        failures.removeValue(forKey: taskID)
        terminalFailures.removeValue(forKey: taskID)
        if let continuation = continuations.removeValue(forKey: taskID) {
            continuation.resume(throwing: CancellationError())
        } else {
            cancelledTaskIDs.insert(taskID)
        }
    }

    func terminalFailure(taskID: Int) -> String? {
        terminalFailures[taskID]
    }

    func didOpen(taskID: Int) -> Bool {
        didOpenTaskIDs.contains(taskID)
    }
}

nonisolated final class LiveDanmakuWebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let openGate = LiveDanmakuWebSocketOpenGate()

    func waitForOpen(_ webSocketTask: URLSessionWebSocketTask) async throws {
        let taskID = webSocketTask.taskIdentifier
        try await withTaskCancellationHandler {
            try await openGate.waitForOpen(taskID: taskID)
        } onCancel: {
            Task { [openGate] in
                await openGate.cancel(taskID: taskID)
            }
        }
    }

    func terminalFailure(for webSocketTask: URLSessionWebSocketTask) async -> String? {
        await openGate.terminalFailure(taskID: webSocketTask.taskIdentifier)
    }

    func didOpen(_ webSocketTask: URLSessionWebSocketTask) async -> Bool {
        await openGate.didOpen(taskID: webSocketTask.taskIdentifier)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        let taskID = webSocketTask.taskIdentifier
        Task { [openGate] in
            await openGate.opened(taskID: taskID)
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let taskID = webSocketTask.taskIdentifier
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }
            ?? "WebSocket 在打开前已关闭"
        let closeDescription = "WebSocket 已关闭（code \(closeCode.rawValue)）：\(reasonText)"
        Task { [openGate] in
            await openGate.failed(taskID: taskID, reason: closeDescription)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, let webSocketTask = task as? URLSessionWebSocketTask else { return }
        let taskID = webSocketTask.taskIdentifier
        Task { [openGate] in
            await openGate.failed(taskID: taskID, reason: error.localizedDescription)
        }
    }
}

nonisolated final class LiveDanmakuService: @unchecked Sendable {
    typealias ItemHandler = @MainActor ([DanmakuItem]) -> Void
    typealias DiagnosticHandler = @MainActor (LiveDanmakuDiagnosticEvent) -> Void

    private enum Operation {
        static let heartbeat = 2
        static let heartbeatReply = 3
        static let command = 5
        static let auth = 7
        static let authReply = 8
    }

    private struct Packet {
        let version: Int
        let operation: Int
        let body: Data
    }

    private enum ConnectionError: LocalizedError, Sendable {
        case noEndpoint
        case webSocketOpenTimedOut
        case authenticationTimedOut
        case authenticationConnectionFailed(String)
        case authenticationRejected(code: Int)
        case endpointsExhausted(attempts: Int, lastEndpoint: String, lastError: String)

        var errorDescription: String? {
            switch self {
            case .noEndpoint:
                return "直播弹幕服务没有返回可用节点"
            case .webSocketOpenTimedOut:
                return "弹幕节点未在限定时间内完成 WebSocket 握手"
            case .authenticationTimedOut:
                return "弹幕节点未在限定时间内返回鉴权结果"
            case .authenticationConnectionFailed(let reason):
                return "鉴权回包前连接已断开：\(reason)"
            case .authenticationRejected(let code):
                return "弹幕节点拒绝鉴权（code \(code)）"
            case .endpointsExhausted(let attempts, let lastEndpoint, let lastError):
                return "已尝试 \(attempts) 次弹幕连接；最后 \(lastEndpoint)：\(lastError)"
            }
        }
    }

    private enum WebSocketConnectionMode: Sendable {
        case direct
        case browserCompatible
        case networkFramework
        case rawHandshake

        var label: String {
            switch self {
            case .direct:
                return "标准连接"
            case .browserCompatible:
                return "兼容连接"
            case .networkFramework:
                return "系统网络连接"
            case .rawHandshake:
                return "原始握手兜底"
            }
        }
    }

    private enum EndpointFailureStage: Sendable, Equatable {
        case handshake
        case authSend
        case authReply
        case receiving

        var label: String {
            switch self {
            case .handshake:
                return "握手前"
            case .authSend:
                return "握手后发送鉴权"
            case .authReply:
                return "鉴权回包前"
            case .receiving:
                return "鉴权完成后收包"
            }
        }
    }

    private struct EndpointConnectionFailure: LocalizedError, Sendable {
        let endpoint: URL
        let mode: WebSocketConnectionMode
        let stage: EndpointFailureStage
        let reason: String

        var errorDescription: String? {
            "\(mode.label) · \(stage.label)：\(reason)"
        }
    }

    private enum AuthenticationReply {
        case accepted
        case rejected(code: Int)
    }

    private struct ParseResult {
        var items: [DanmakuItem] = []
        var events: [LiveDanmakuDiagnosticEvent] = []

        mutating func append(_ other: ParseResult) {
            items.append(contentsOf: other.items)
            events.append(contentsOf: other.events)
        }
    }

    private struct LiveMessagePayload {
        let text: String
        let color: UInt32
        let mode: Int
        let fontSize: Double
        let senderName: String?
        let inlineEmotes: [String: BiliInlineEmote]

        init(
            text: String,
            color: UInt32,
            mode: Int,
            fontSize: Double,
            senderName: String? = nil,
            inlineEmotes: [String: BiliInlineEmote] = [:]
        ) {
            self.text = text
            self.color = color
            self.mode = mode
            self.fontSize = fontSize
            self.senderName = senderName
            self.inlineEmotes = inlineEmotes
        }
    }

    private let roomID: Int
    private let api: BiliAPIClient
    private let session: URLSession
    private let onItems: ItemHandler
    private let onDiagnostics: DiagnosticHandler?
    private let logger = Logger(subsystem: "cc.bili", category: "LiveDanmaku")
    private let stateQueue = DispatchQueue(label: "cc.bili.live-danmaku.state")
    private var task: URLSessionWebSocketTask?
    private var networkWebSocket: LiveDanmakuNetworkWebSocket?
    private var rawWebSocket: LiveDanmakuRawWebSocket?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var isStopped = false
    private var reconnectAttempt = 0
    private let startDate = Date()
    private static let authenticationTimeoutNanoseconds: UInt64 = 5_000_000_000

    init(
        roomID: Int,
        api: BiliAPIClient,
        onDiagnostics: DiagnosticHandler? = nil,
        onItems: @escaping ItemHandler
    ) {
        self.roomID = roomID
        self.api = api
        self.onDiagnostics = onDiagnostics
        self.onItems = onItems
        self.session = URLSession(configuration: .default)
    }

    deinit {
        stop()
        session.invalidateAndCancel()
    }

    func start() {
        stateQueue.async { [weak self] in
            guard let self,
                  self.task == nil,
                  self.networkWebSocket == nil,
                  self.rawWebSocket == nil,
                  !self.isStopped
            else { return }
            self.emitDiagnostic(.serviceStarted(roomID: self.roomID))
            self.connect()
        }
    }

    func stop() {
        stateQueue.sync {
            isStopped = true
            heartbeatTask?.cancel()
            receiveTask?.cancel()
            reconnectTask?.cancel()
            heartbeatTask = nil
            receiveTask = nil
            reconnectTask = nil
            reconnectAttempt = 0
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            networkWebSocket?.cancel()
            networkWebSocket = nil
            rawWebSocket?.cancel()
            rawWebSocket = nil
            emitDiagnostic(.stopped)
        }
    }

    private func connect() {
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let context = await api.liveDanmakuClientContext(roomID: roomID)
                emitDiagnostic(
                    .contextReady(
                        uid: context.uid,
                        hasCookie: !context.cookieHeader.isEmpty,
                        hasBuvid: !context.buvid.isEmpty
                    )
                )
                emitDiagnostic(.configRequestStarted)
                let info = try await api.fetchLiveDanmakuConnectionInfo(
                    roomID: roomID,
                    cookieHeader: context.cookieHeader,
                    transportSession: session
                )
                let endpoints = Self.webSocketEndpoints(for: info)
                guard let firstEndpoint = endpoints.first else { throw ConnectionError.noEndpoint }
                logger.notice(
                    "liveDanmaku config room=\(self.roomID, privacy: .public) uid=\(context.uid, privacy: .public) cookie=\(!context.cookieHeader.isEmpty, privacy: .public) tokenLength=\(info.token?.count ?? 0, privacy: .public) endpoints=\(endpoints.count, privacy: .public)"
                )
                emitDiagnostic(
                    .configLoaded(
                        hostCount: info.hostList.count,
                        hasToken: info.token?.isEmpty == false,
                        selectedEndpoint: firstEndpoint.absoluteString
                    )
                )
                try await connectToEndpointCandidates(
                    endpoints,
                    token: info.token,
                    uid: context.uid,
                    compatibilityHeaders: context.headers
                )
            } catch {
                emitDiagnostic(.reconnectScheduled(error: error.localizedDescription))
                logger.warning("liveDanmaku reconnect room=\(self.roomID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                await scheduleReconnectIfNeeded()
            }
        }
    }

    private func emitDiagnostic(_ event: LiveDanmakuDiagnosticEvent) {
        guard let onDiagnostics else { return }
        Task { @MainActor in
            onDiagnostics(event)
        }
    }

    private func setTask(_ webSocketTask: URLSessionWebSocketTask) async -> Bool {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self, !self.isStopped else {
                    webSocketTask.cancel(with: .goingAway, reason: nil)
                    continuation.resume(returning: false)
                    return
                }
                self.task?.cancel(with: .goingAway, reason: nil)
                self.networkWebSocket?.cancel()
                self.networkWebSocket = nil
                self.rawWebSocket?.cancel()
                self.rawWebSocket = nil
                self.task = webSocketTask
                continuation.resume(returning: true)
            }
        }
    }

    private func isCurrentTask(_ webSocketTask: URLSessionWebSocketTask) async -> Bool {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self, !self.isStopped else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: self.task === webSocketTask)
            }
        }
    }

    private func setNetworkWebSocket(_ webSocket: LiveDanmakuNetworkWebSocket) async -> Bool {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self, !self.isStopped else {
                    webSocket.cancel()
                    continuation.resume(returning: false)
                    return
                }
                self.task?.cancel(with: .goingAway, reason: nil)
                self.task = nil
                self.networkWebSocket?.cancel()
                self.rawWebSocket?.cancel()
                self.rawWebSocket = nil
                self.networkWebSocket = webSocket
                continuation.resume(returning: true)
            }
        }
    }

    private func isCurrentNetworkWebSocket(_ webSocket: LiveDanmakuNetworkWebSocket) async -> Bool {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self, !self.isStopped else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: self.networkWebSocket === webSocket)
            }
        }
    }

    private func setRawWebSocket(_ webSocket: LiveDanmakuRawWebSocket) async -> Bool {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self, !self.isStopped else {
                    webSocket.cancel()
                    continuation.resume(returning: false)
                    return
                }
                self.task?.cancel(with: .goingAway, reason: nil)
                self.task = nil
                self.networkWebSocket?.cancel()
                self.networkWebSocket = nil
                self.rawWebSocket?.cancel()
                self.rawWebSocket = webSocket
                continuation.resume(returning: true)
            }
        }
    }

    private func isCurrentRawWebSocket(_ webSocket: LiveDanmakuRawWebSocket) async -> Bool {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self, !self.isStopped else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: self.rawWebSocket === webSocket)
            }
        }
    }

    private func connectToEndpointCandidates(
        _ endpoints: [URL],
        token: String?,
        uid: Int,
        compatibilityHeaders: [String: String]
    ) async throws {
        let compatibleFailures = try await connectEndpointPass(
            endpoints,
            token: token,
            uid: uid,
            mode: .browserCompatible,
            compatibilityHeaders: compatibilityHeaders,
            attemptOffset: 0,
            totalAttemptCount: endpoints.count * 4
        )
        guard shouldTryDirectPass(after: compatibleFailures) else {
            throw endpointsExhaustedError(from: compatibleFailures)
        }

        let directFailures = try await connectEndpointPass(
            endpoints,
            token: token,
            uid: uid,
            mode: .direct,
            compatibilityHeaders: [:],
            attemptOffset: compatibleFailures.count,
            totalAttemptCount: endpoints.count * 4
        )
        guard shouldTryNetworkFrameworkPass(after: directFailures) else {
            throw endpointsExhaustedError(from: compatibleFailures + directFailures)
        }

        let networkFrameworkFailures = try await connectNetworkFrameworkPass(
            endpoints,
            token: token,
            uid: uid,
            headers: compatibilityHeaders,
            attemptOffset: compatibleFailures.count + directFailures.count,
            totalAttemptCount: endpoints.count * 4
        )
        guard shouldTryRawHandshakePass(after: networkFrameworkFailures) else {
            throw endpointsExhaustedError(
                from: compatibleFailures + directFailures + networkFrameworkFailures
            )
        }

        let rawHandshakeFailures = try await connectRawHandshakePass(
            endpoints,
            token: token,
            uid: uid,
            headers: compatibilityHeaders,
            attemptOffset: compatibleFailures.count + directFailures.count + networkFrameworkFailures.count,
            totalAttemptCount: endpoints.count * 4
        )
        throw endpointsExhaustedError(
            from: compatibleFailures + directFailures + networkFrameworkFailures + rawHandshakeFailures
        )
    }

    private func connectEndpointPass(
        _ endpoints: [URL],
        token: String?,
        uid: Int,
        mode: WebSocketConnectionMode,
        compatibilityHeaders: [String: String],
        attemptOffset: Int,
        totalAttemptCount: Int
    ) async throws -> [EndpointConnectionFailure] {
        var failures: [EndpointConnectionFailure] = []

        for (index, endpoint) in endpoints.enumerated() {
            guard !Task.isCancelled else { throw CancellationError() }

            let webSocketTask: URLSessionWebSocketTask
            switch mode {
            case .direct:
                webSocketTask = session.webSocketTask(with: endpoint)
            case .browserCompatible:
                webSocketTask = session.webSocketTask(
                    with: Self.browserCompatibleWebSocketRequest(
                        endpoint: endpoint,
                        headers: compatibilityHeaders
                    )
                )
            case .networkFramework:
                preconditionFailure("Network.framework uses its dedicated connection pass")
            case .rawHandshake:
                preconditionFailure("原始握手使用专用连接通道")
            }
            guard await setTask(webSocketTask) else { throw CancellationError() }
            emitDiagnostic(
                .endpointAttempt(
                    index: attemptOffset + index + 1,
                    total: totalAttemptCount,
                    endpoint: endpoint.absoluteString
                )
            )
            webSocketTask.resume()
            // Match the transport ordering used by the working reference clients:
            // URLSession queues the binary authentication frame until its HTTP
            // upgrade completes, avoiding a separate didOpen scheduling window.
            emitDiagnostic(.webSocketResumed(endpoint: endpoint.absoluteString))

            do {
                try await sendAuth(token: token, uid: uid, on: webSocketTask)
            } catch is CancellationError {
                webSocketTask.cancel(with: .goingAway, reason: nil)
                throw CancellationError()
            } catch {
                failures.append(
                    await endpointFailure(
                        endpoint: endpoint,
                        webSocketTask: webSocketTask,
                        mode: mode,
                        stage: .authSend,
                        error: error
                    )
                )
                continue
            }

            do {
                try await receiveLoop(webSocketTask, awaitsAuthentication: true)
                return []
            } catch is CancellationError {
                webSocketTask.cancel(with: .goingAway, reason: nil)
                throw CancellationError()
            } catch {
                failures.append(
                    await endpointFailure(
                        endpoint: endpoint,
                        webSocketTask: webSocketTask,
                        mode: mode,
                        stage: receiveFailureStage(for: error),
                        error: error
                    )
                )
            }
        }

        return failures
    }

    private func connectNetworkFrameworkPass(
        _ endpoints: [URL],
        token: String?,
        uid: Int,
        headers: [String: String],
        attemptOffset: Int,
        totalAttemptCount: Int
    ) async throws -> [EndpointConnectionFailure] {
        var failures: [EndpointConnectionFailure] = []

        for (index, endpoint) in endpoints.enumerated() {
            guard !Task.isCancelled else { throw CancellationError() }

            let webSocket = LiveDanmakuNetworkWebSocket(endpoint: endpoint, headers: headers)
            guard await setNetworkWebSocket(webSocket) else { throw CancellationError() }
            emitDiagnostic(
                .endpointAttempt(
                    index: attemptOffset + index + 1,
                    total: totalAttemptCount,
                    endpoint: endpoint.absoluteString
                )
            )

            do {
                try await waitForNetworkWebSocketOpen(webSocket)
                emitDiagnostic(.webSocketResumed(endpoint: endpoint.absoluteString))
            } catch is CancellationError {
                webSocket.cancel()
                throw CancellationError()
            } catch {
                failures.append(
                    await endpointFailure(
                        endpoint: endpoint,
                        networkWebSocket: webSocket,
                        mode: .networkFramework,
                        stage: .handshake,
                        error: error
                    )
                )
                continue
            }

            do {
                try await sendAuth(token: token, uid: uid, on: webSocket)
            } catch is CancellationError {
                webSocket.cancel()
                throw CancellationError()
            } catch {
                failures.append(
                    await endpointFailure(
                        endpoint: endpoint,
                        networkWebSocket: webSocket,
                        mode: .networkFramework,
                        stage: .authSend,
                        error: error
                    )
                )
                continue
            }

            do {
                try await receiveLoop(webSocket, awaitsAuthentication: true)
                return []
            } catch is CancellationError {
                webSocket.cancel()
                throw CancellationError()
            } catch {
                failures.append(
                    await endpointFailure(
                        endpoint: endpoint,
                        networkWebSocket: webSocket,
                        mode: .networkFramework,
                        stage: receiveFailureStage(for: error),
                        error: error
                    )
                )
            }
        }

        return failures
    }

    private func connectRawHandshakePass(
        _ endpoints: [URL],
        token: String?,
        uid: Int,
        headers: [String: String],
        attemptOffset: Int,
        totalAttemptCount: Int
    ) async throws -> [EndpointConnectionFailure] {
        var failures: [EndpointConnectionFailure] = []

        for (index, endpoint) in endpoints.enumerated() {
            guard !Task.isCancelled else { throw CancellationError() }

            let webSocket = LiveDanmakuRawWebSocket(endpoint: endpoint, headers: headers)
            guard await setRawWebSocket(webSocket) else { throw CancellationError() }
            emitDiagnostic(
                .endpointAttempt(
                    index: attemptOffset + index + 1,
                    total: totalAttemptCount,
                    endpoint: endpoint.absoluteString
                )
            )

            do {
                try await waitForRawWebSocketOpen(webSocket)
                emitDiagnostic(.webSocketResumed(endpoint: endpoint.absoluteString))
            } catch is CancellationError {
                webSocket.cancel()
                throw CancellationError()
            } catch {
                failures.append(
                    await endpointFailure(
                        endpoint: endpoint,
                        rawWebSocket: webSocket,
                        mode: .rawHandshake,
                        stage: .handshake,
                        error: error
                    )
                )
                continue
            }

            do {
                try await sendAuth(token: token, uid: uid, on: webSocket)
            } catch is CancellationError {
                webSocket.cancel()
                throw CancellationError()
            } catch {
                failures.append(
                    await endpointFailure(
                        endpoint: endpoint,
                        rawWebSocket: webSocket,
                        mode: .rawHandshake,
                        stage: .authSend,
                        error: error
                    )
                )
                continue
            }

            do {
                try await receiveLoop(webSocket, awaitsAuthentication: true)
                return []
            } catch is CancellationError {
                webSocket.cancel()
                throw CancellationError()
            } catch {
                failures.append(
                    await endpointFailure(
                        endpoint: endpoint,
                        rawWebSocket: webSocket,
                        mode: .rawHandshake,
                        stage: receiveFailureStage(for: error),
                        error: error
                    )
                )
            }
        }

        return failures
    }

    private func endpointFailure(
        endpoint: URL,
        webSocketTask: URLSessionWebSocketTask,
        mode: WebSocketConnectionMode,
        stage: EndpointFailureStage,
        error: Error
    ) async -> EndpointConnectionFailure {
        let reason = error.localizedDescription
        let failure = EndpointConnectionFailure(
            endpoint: endpoint,
            mode: mode,
            stage: stage,
            reason: reason
        )
        emitDiagnostic(.endpointFailed(endpoint: endpoint.absoluteString, error: failure.errorDescription ?? reason))
        webSocketTask.cancel(with: .goingAway, reason: nil)
        await clearCurrentTask(webSocketTask)
        logger.notice(
            "liveDanmaku endpoint failed room=\(self.roomID, privacy: .public) host=\(endpoint.host ?? endpoint.absoluteString, privacy: .public) error=\(failure.errorDescription ?? reason, privacy: .public)"
        )
        return failure
    }

    private func endpointFailure(
        endpoint: URL,
        networkWebSocket: LiveDanmakuNetworkWebSocket,
        mode: WebSocketConnectionMode,
        stage: EndpointFailureStage,
        error: Error
    ) async -> EndpointConnectionFailure {
        await Task.yield()
        let terminalFailure = await networkWebSocket.terminalFailure()
        let reason = terminalFailure ?? error.localizedDescription
        let failure = EndpointConnectionFailure(
            endpoint: endpoint,
            mode: mode,
            stage: stage,
            reason: reason
        )
        emitDiagnostic(.endpointFailed(endpoint: endpoint.absoluteString, error: failure.errorDescription ?? reason))
        networkWebSocket.cancel()
        await clearCurrentNetworkWebSocket(networkWebSocket)
        logger.notice(
            "liveDanmaku network endpoint failed room=\(self.roomID, privacy: .public) host=\(endpoint.host ?? endpoint.absoluteString, privacy: .public) error=\(failure.errorDescription ?? reason, privacy: .public)"
        )
        return failure
    }

    private func endpointFailure(
        endpoint: URL,
        rawWebSocket: LiveDanmakuRawWebSocket,
        mode: WebSocketConnectionMode,
        stage: EndpointFailureStage,
        error: Error
    ) async -> EndpointConnectionFailure {
        await Task.yield()
        let terminalFailure = await rawWebSocket.terminalFailure()
        let reason = terminalFailure ?? error.localizedDescription
        let failure = EndpointConnectionFailure(
            endpoint: endpoint,
            mode: mode,
            stage: stage,
            reason: reason
        )
        emitDiagnostic(.endpointFailed(endpoint: endpoint.absoluteString, error: failure.errorDescription ?? reason))
        rawWebSocket.cancel()
        await clearCurrentRawWebSocket(rawWebSocket)
        logger.notice(
            "liveDanmaku raw endpoint failed room=\(self.roomID, privacy: .public) host=\(endpoint.host ?? endpoint.absoluteString, privacy: .public) error=\(failure.errorDescription ?? reason, privacy: .public)"
        )
        return failure
    }

    private func receiveFailureStage(for error: Error) -> EndpointFailureStage {
        guard let connectionError = error as? ConnectionError else { return .receiving }
        if case .authenticationConnectionFailed = connectionError {
            return .authReply
        }
        return .receiving
    }

    private func shouldTryDirectPass(after failures: [EndpointConnectionFailure]) -> Bool {
        guard !failures.isEmpty else { return false }
        return failures.allSatisfy { failure in
            failure.stage == .handshake
                || failure.stage == .authSend
                || failure.stage == .authReply
        }
    }

    private func shouldTryNetworkFrameworkPass(after failures: [EndpointConnectionFailure]) -> Bool {
        shouldTryDirectPass(after: failures)
    }

    private func shouldTryRawHandshakePass(after failures: [EndpointConnectionFailure]) -> Bool {
        shouldTryDirectPass(after: failures)
    }

    private func endpointsExhaustedError(from failures: [EndpointConnectionFailure]) -> ConnectionError {
        guard let lastFailure = failures.last else {
            return .noEndpoint
        }
        return .endpointsExhausted(
            attempts: failures.count,
            lastEndpoint: lastFailure.endpoint.host ?? lastFailure.endpoint.absoluteString,
            lastError: lastFailure.errorDescription ?? lastFailure.reason
        )
    }

    private func clearCurrentTask(_ webSocketTask: URLSessionWebSocketTask) async {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                if self.task === webSocketTask {
                    self.task = nil
                }
                self.heartbeatTask?.cancel()
                self.heartbeatTask = nil
                continuation.resume()
            }
        }
    }

    private func clearCurrentNetworkWebSocket(_ webSocket: LiveDanmakuNetworkWebSocket) async {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                if self.networkWebSocket === webSocket {
                    self.networkWebSocket = nil
                }
                self.heartbeatTask?.cancel()
                self.heartbeatTask = nil
                continuation.resume()
            }
        }
    }

    private func clearCurrentRawWebSocket(_ webSocket: LiveDanmakuRawWebSocket) async {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                if self.rawWebSocket === webSocket {
                    self.rawWebSocket = nil
                }
                self.heartbeatTask?.cancel()
                self.heartbeatTask = nil
                continuation.resume()
            }
        }
    }

    private func sendAuth(
        token: String?,
        uid: Int,
        on webSocketTask: URLSessionWebSocketTask
    ) async throws {
        let body = try Self.authenticationBody(roomID: roomID, uid: uid, token: token)
        try await sendPacket(operation: Operation.auth, body: body, on: webSocketTask)
        emitDiagnostic(.authSent(hasToken: token?.isEmpty == false))
    }

    private func sendAuth(
        token: String?,
        uid: Int,
        on webSocket: LiveDanmakuNetworkWebSocket
    ) async throws {
        let body = try Self.authenticationBody(roomID: roomID, uid: uid, token: token)
        try await sendPacket(operation: Operation.auth, body: body, on: webSocket)
        emitDiagnostic(.authSent(hasToken: token?.isEmpty == false))
    }

    private func sendAuth(
        token: String?,
        uid: Int,
        on webSocket: LiveDanmakuRawWebSocket
    ) async throws {
        let body = try Self.authenticationBody(roomID: roomID, uid: uid, token: token)
        try await sendPacket(operation: Operation.auth, body: body, on: webSocket)
        emitDiagnostic(.authSent(hasToken: token?.isEmpty == false))
    }

    private func waitForNetworkWebSocketOpen(_ webSocket: LiveDanmakuNetworkWebSocket) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await webSocket.open()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.authenticationTimeoutNanoseconds)
                webSocket.cancel()
                throw ConnectionError.webSocketOpenTimedOut
            }
            guard try await group.next() != nil else {
                throw ConnectionError.webSocketOpenTimedOut
            }
            group.cancelAll()
        }
    }

    private func waitForRawWebSocketOpen(_ webSocket: LiveDanmakuRawWebSocket) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await webSocket.open()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.authenticationTimeoutNanoseconds)
                webSocket.cancel()
                throw ConnectionError.webSocketOpenTimedOut
            }
            guard try await group.next() != nil else {
                throw ConnectionError.webSocketOpenTimedOut
            }
            group.cancelAll()
        }
    }

    private func startHeartbeat(on webSocketTask: URLSessionWebSocketTask) async {
        heartbeatTask?.cancel()
        emitDiagnostic(.heartbeatStarted)
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                guard await self.isCurrentTask(webSocketTask) else { return }
                do {
                    try await self.sendPacket(
                        operation: Operation.heartbeat,
                        body: Data(),
                        on: webSocketTask
                    )
                    self.emitDiagnostic(.heartbeatSent)
                } catch {
                    self.emitDiagnostic(.reconnectScheduled(error: error.localizedDescription))
                }
            }
        }
    }

    private func startHeartbeat(on webSocket: LiveDanmakuNetworkWebSocket) async {
        heartbeatTask?.cancel()
        emitDiagnostic(.heartbeatStarted)
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                guard await self.isCurrentNetworkWebSocket(webSocket) else { return }
                do {
                    try await self.sendPacket(
                        operation: Operation.heartbeat,
                        body: Data(),
                        on: webSocket
                    )
                    self.emitDiagnostic(.heartbeatSent)
                } catch {
                    self.emitDiagnostic(.reconnectScheduled(error: error.localizedDescription))
                }
            }
        }
    }

    private func startHeartbeat(on webSocket: LiveDanmakuRawWebSocket) async {
        heartbeatTask?.cancel()
        emitDiagnostic(.heartbeatStarted)
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                guard await self.isCurrentRawWebSocket(webSocket) else { return }
                do {
                    try await self.sendPacket(
                        operation: Operation.heartbeat,
                        body: Data(),
                        on: webSocket
                    )
                    self.emitDiagnostic(.heartbeatSent)
                } catch {
                    self.emitDiagnostic(.reconnectScheduled(error: error.localizedDescription))
                }
            }
        }
    }

    private func sendPacket(
        operation: Int,
        body: Data,
        on webSocketTask: URLSessionWebSocketTask
    ) async throws {
        let packet = Self.encodePacket(operation: operation, body: body)
        try await webSocketTask.send(.data(packet))
    }

    private func sendPacket(
        operation: Int,
        body: Data,
        on webSocket: LiveDanmakuNetworkWebSocket
    ) async throws {
        let packet = Self.encodePacket(operation: operation, body: body)
        try await webSocket.send(packet)
    }

    private func sendPacket(
        operation: Int,
        body: Data,
        on webSocket: LiveDanmakuRawWebSocket
    ) async throws {
        let packet = Self.encodePacket(operation: operation, body: body)
        try await webSocket.send(packet)
    }

    private func receiveLoop(
        _ webSocketTask: URLSessionWebSocketTask,
        awaitsAuthentication: Bool
    ) async throws {
        var awaitsAuthentication = awaitsAuthentication
        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await receiveMessage(
                    on: webSocketTask,
                    authenticationTimeout: awaitsAuthentication
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if awaitsAuthentication {
                    throw ConnectionError.authenticationConnectionFailed(error.localizedDescription)
                }
                throw error
            }
            let data: Data?
            switch message {
            case .data(let value):
                data = value
            case .string(let value):
                data = Data(value.utf8)
            @unknown default:
                data = nil
            }
            guard let data else { continue }
            if awaitsAuthentication, let authenticationReply = Self.authenticationReply(in: data) {
                switch authenticationReply {
                case .accepted:
                    awaitsAuthentication = false
                    markConnectionHealthy()
                    await startHeartbeat(on: webSocketTask)
                case .rejected(let code):
                    throw ConnectionError.authenticationRejected(code: code)
                }
            } else if !awaitsAuthentication {
                markConnectionHealthy()
            }
            emitDiagnostic(.messageReceived(byteCount: data.count))
            let result = Self.parseItems(from: data, roomID: roomID, startDate: startDate)
            result.events.forEach(emitDiagnostic)
            let items = result.items
            guard !items.isEmpty else { continue }
            emitDiagnostic(.itemsDelivered(count: items.count))
            await onItems(items)
        }
    }

    private func receiveLoop(
        _ webSocket: LiveDanmakuNetworkWebSocket,
        awaitsAuthentication: Bool
    ) async throws {
        var awaitsAuthentication = awaitsAuthentication
        while !Task.isCancelled {
            let data: Data
            do {
                data = try await receiveMessage(
                    on: webSocket,
                    authenticationTimeout: awaitsAuthentication
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if awaitsAuthentication {
                    throw ConnectionError.authenticationConnectionFailed(error.localizedDescription)
                }
                throw error
            }
            if awaitsAuthentication, let authenticationReply = Self.authenticationReply(in: data) {
                switch authenticationReply {
                case .accepted:
                    awaitsAuthentication = false
                    markConnectionHealthy()
                    await startHeartbeat(on: webSocket)
                case .rejected(let code):
                    throw ConnectionError.authenticationRejected(code: code)
                }
            } else if !awaitsAuthentication {
                markConnectionHealthy()
            }
            emitDiagnostic(.messageReceived(byteCount: data.count))
            let result = Self.parseItems(from: data, roomID: roomID, startDate: startDate)
            result.events.forEach(emitDiagnostic)
            let items = result.items
            guard !items.isEmpty else { continue }
            emitDiagnostic(.itemsDelivered(count: items.count))
            await onItems(items)
        }
    }

    private func receiveLoop(
        _ webSocket: LiveDanmakuRawWebSocket,
        awaitsAuthentication: Bool
    ) async throws {
        var awaitsAuthentication = awaitsAuthentication
        while !Task.isCancelled {
            let data: Data
            do {
                data = try await receiveMessage(
                    on: webSocket,
                    authenticationTimeout: awaitsAuthentication
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if awaitsAuthentication {
                    throw ConnectionError.authenticationConnectionFailed(error.localizedDescription)
                }
                throw error
            }
            if awaitsAuthentication, let authenticationReply = Self.authenticationReply(in: data) {
                switch authenticationReply {
                case .accepted:
                    awaitsAuthentication = false
                    markConnectionHealthy()
                    await startHeartbeat(on: webSocket)
                case .rejected(let code):
                    throw ConnectionError.authenticationRejected(code: code)
                }
            } else if !awaitsAuthentication {
                markConnectionHealthy()
            }
            emitDiagnostic(.messageReceived(byteCount: data.count))
            let result = Self.parseItems(from: data, roomID: roomID, startDate: startDate)
            result.events.forEach(emitDiagnostic)
            let items = result.items
            guard !items.isEmpty else { continue }
            emitDiagnostic(.itemsDelivered(count: items.count))
            await onItems(items)
        }
    }

    private func receiveMessage(
        on webSocketTask: URLSessionWebSocketTask,
        authenticationTimeout: Bool
    ) async throws -> URLSessionWebSocketTask.Message {
        guard authenticationTimeout else {
            return try await webSocketTask.receive()
        }

        return try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                try await webSocketTask.receive()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.authenticationTimeoutNanoseconds)
                webSocketTask.cancel(with: .goingAway, reason: nil)
                throw ConnectionError.authenticationTimedOut
            }
            guard let message = try await group.next() else {
                throw ConnectionError.authenticationTimedOut
            }
            group.cancelAll()
            return message
        }
    }

    private func receiveMessage(
        on webSocket: LiveDanmakuNetworkWebSocket,
        authenticationTimeout: Bool
    ) async throws -> Data {
        guard authenticationTimeout else {
            return try await webSocket.receive()
        }

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await webSocket.receive()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.authenticationTimeoutNanoseconds)
                webSocket.cancel()
                throw ConnectionError.authenticationTimedOut
            }
            guard let message = try await group.next() else {
                throw ConnectionError.authenticationTimedOut
            }
            group.cancelAll()
            return message
        }
    }

    private func receiveMessage(
        on webSocket: LiveDanmakuRawWebSocket,
        authenticationTimeout: Bool
    ) async throws -> Data {
        guard authenticationTimeout else {
            return try await webSocket.receive()
        }

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await webSocket.receive()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: Self.authenticationTimeoutNanoseconds)
                webSocket.cancel()
                throw ConnectionError.authenticationTimedOut
            }
            guard let message = try await group.next() else {
                throw ConnectionError.authenticationTimedOut
            }
            group.cancelAll()
            return message
        }
    }

    private func scheduleReconnectIfNeeded() async {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self, !self.isStopped else {
                    continuation.resume()
                    return
                }
                self.task?.cancel(with: .goingAway, reason: nil)
                self.task = nil
                self.networkWebSocket?.cancel()
                self.networkWebSocket = nil
                self.rawWebSocket?.cancel()
                self.rawWebSocket = nil
                self.heartbeatTask?.cancel()
                self.heartbeatTask = nil
                self.reconnectTask?.cancel()
                let delayNanoseconds = Self.reconnectDelayNanoseconds(for: self.reconnectAttempt)
                self.reconnectAttempt = min(self.reconnectAttempt + 1, 5)
                self.reconnectTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                    guard !Task.isCancelled else { return }
                    self?.stateQueue.async { [weak self] in
                        guard let self,
                              !self.isStopped,
                              self.task == nil,
                              self.networkWebSocket == nil,
                              self.rawWebSocket == nil
                        else { return }
                        self.connect()
                    }
                }
                continuation.resume()
            }
        }
    }

    private func markConnectionHealthy() {
        stateQueue.async { [weak self] in
            self?.reconnectAttempt = 0
        }
    }

    private static func reconnectDelayNanoseconds(for attempt: Int) -> UInt64 {
        let delays: [UInt64] = [
            2_000_000_000,
            4_000_000_000,
            8_000_000_000,
            15_000_000_000,
            30_000_000_000,
            45_000_000_000
        ]
        return delays[min(max(attempt, 0), delays.count - 1)]
    }

    private static func webSocketEndpoints(for info: LiveDanmakuConnectionInfoData) -> [URL] {
        let fallback = URL(string: "wss://broadcastlv.chat.bilibili.com:443/sub")
        var seen = Set<URL>()
        return (info.hostList.compactMap(\.webSocketURL) + [fallback].compactMap { $0 })
            .filter { seen.insert($0).inserted }
    }

    static func browserCompatibleWebSocketRequest(
        endpoint: URL,
        headers: [String: String]
    ) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 30
        for (key, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    static func authenticationBody(
        roomID: Int,
        uid: Int,
        token: String?
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "roomid": roomID,
                "uid": uid,
                "protover": 3,
                "platform": "web",
                "type": 2,
                "key": token ?? ""
            ]
        )
    }

    private static func authenticationReply(in data: Data) -> AuthenticationReply? {
        for packet in parsePackets(from: data) where packet.operation == Operation.authReply {
            guard let payload = try? JSONSerialization.jsonObject(with: packet.body) as? [String: Any] else {
                return .rejected(code: -1)
            }
            let code = intValue(payload["code"]) ?? -1
            return code == 0 ? .accepted : .rejected(code: code)
        }
        return nil
    }

    private static func encodePacket(operation: Int, body: Data) -> Data {
        var data = Data()
        data.appendBigEndianUInt32(UInt32(16 + body.count))
        data.appendBigEndianUInt16(16)
        data.appendBigEndianUInt16(1)
        data.appendBigEndianUInt32(UInt32(operation))
        data.appendBigEndianUInt32(1)
        data.append(body)
        return data
    }

    private static func parseItems(from data: Data, roomID: Int, startDate: Date) -> ParseResult {
        var result = ParseResult()
        for packet in parsePackets(from: data) {
            result.events.append(
                .packetReceived(
                    operation: packet.operation,
                    version: packet.version,
                    bodyBytes: packet.body.count
                )
            )
            switch packet.operation {
            case Operation.command:
                result.events.append(.commandPacket(version: packet.version, bodyBytes: packet.body.count))
                result.append(parseCommandPacket(packet, roomID: roomID, startDate: startDate))
            case Operation.authReply:
                result.events.append(.authReply)
            case Operation.heartbeatReply:
                result.events.append(.heartbeatReply)
            default:
                break
            }
        }
        return result
    }

    private static func parseCommandPacket(_ packet: Packet, roomID: Int, startDate: Date) -> ParseResult {
        switch packet.version {
        case 0, 1:
            return parseJSONCommands(packet.body, roomID: roomID, startDate: startDate)
        case 2:
            guard let inflated = inflate(packet.body, algorithm: COMPRESSION_ZLIB) else {
                return ParseResult(events: [.inflateFailed(version: packet.version)])
            }
            var result = ParseResult(events: [.inflateSucceeded(version: packet.version, byteCount: inflated.count)])
            result.append(parseInflatedCommandBody(inflated, roomID: roomID, startDate: startDate))
            return result
        case 3:
            guard let inflated = inflate(packet.body, algorithm: COMPRESSION_BROTLI)
                ?? inflate(packet.body, algorithm: COMPRESSION_ZLIB)
            else {
                return ParseResult(events: [.inflateFailed(version: packet.version)])
            }
            var result = ParseResult(events: [.inflateSucceeded(version: packet.version, byteCount: inflated.count)])
            result.append(parseInflatedCommandBody(inflated, roomID: roomID, startDate: startDate))
            return result
        default:
            return ParseResult()
        }
    }

    private static func parseInflatedCommandBody(_ data: Data, roomID: Int, startDate: Date) -> ParseResult {
        let nestedItems = parseItems(from: data, roomID: roomID, startDate: startDate)
        if !nestedItems.items.isEmpty {
            return nestedItems
        }
        var result = nestedItems
        result.append(parseJSONCommands(data, roomID: roomID, startDate: startDate))
        return result
    }

    private static func parsePackets(from data: Data) -> [Packet] {
        var packets: [Packet] = []
        var offset = 0
        let bytes = [UInt8](data)
        while offset + 16 <= bytes.count {
            let packetLength = Int(bytes.bigEndianUInt32(at: offset))
            let headerLength = Int(bytes.bigEndianUInt16(at: offset + 4))
            let version = Int(bytes.bigEndianUInt16(at: offset + 6))
            let operation = Int(bytes.bigEndianUInt32(at: offset + 8))
            guard packetLength >= headerLength,
                  headerLength >= 16,
                  offset + packetLength <= bytes.count
            else { break }
            let body = Data(bytes[(offset + headerLength)..<(offset + packetLength)])
            packets.append(Packet(version: version, operation: operation, body: body))
            offset += packetLength
        }
        return packets
    }

    private static func parseJSONCommands(_ data: Data, roomID: Int, startDate: Date) -> ParseResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return ParseResult(events: [.jsonParseFailed(byteCount: data.count)])
        }
        if let commands = object as? [[String: Any]] {
            var result = ParseResult()
            for command in commands {
                result.append(parseJSONCommand(command, roomID: roomID, startDate: startDate))
            }
            return result
        }
        guard let command = object as? [String: Any] else { return ParseResult() }
        return parseJSONCommand(command, roomID: roomID, startDate: startDate)
    }

    private static func parseJSONCommand(_ object: [String: Any], roomID: Int, startDate: Date) -> ParseResult {
        guard let command = object["cmd"] as? String else { return ParseResult() }
        var result = ParseResult(events: [.commandReceived(name: command)])
        guard let payload = liveMessagePayload(for: command, object: object) else { return result }

        let trimmedText = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return result }
        let currentTime = max(0, Date().timeIntervalSince(startDate))
        let commandID = command.replacingOccurrences(
            of: #"[^A-Za-z0-9_:-]"#,
            with: "-",
            options: .regularExpression
        )
        let id = "live-\(roomID)-\(Int(currentTime * 1000))-\(commandID)-\(UUID().uuidString)"
        result.items = [
            DanmakuItem(
                id: id,
                time: currentTime,
                mode: payload.mode,
                fontSize: payload.fontSize,
                color: payload.color,
                text: trimmedText,
                senderName: payload.senderName,
                inlineEmotes: payload.inlineEmotes
            )
        ]
        result.events.append(.danmakuParsed(text: trimmedText))
        return result
    }

    static func parsedItems(
        for command: [String: Any],
        roomID: Int,
        startDate: Date
    ) -> [DanmakuItem] {
        parseJSONCommand(command, roomID: roomID, startDate: startDate).items
    }

    private static func liveMessagePayload(for command: String, object: [String: Any]) -> LiveMessagePayload? {
        let baseCommand = commandBaseName(command)
        switch baseCommand {
        case "DANMU_MSG":
            return danmakuMessagePayload(from: object)
        case "SUPER_CHAT_MESSAGE", "SUPER_CHAT_MESSAGE_JPN":
            return superChatMessagePayload(from: object)
        case "DM_INTERACTION":
            return textMessagePayload(
                from: object,
                keys: ["msg", "message", "content", "text", "desc"],
                color: 0x7DD3FC
            )
        case "INTERACT_WORD":
            return interactWordPayload(from: object)
        case "ENTRY_EFFECT":
            return entryEffectPayload(from: object)
        case "NOTICE_MSG":
            return noticeMessagePayload(from: object)
        case "SEND_GIFT", "COMBO_SEND":
            return giftMessagePayload(from: object)
        case "GUARD_BUY":
            return guardBuyPayload(from: object)
        default:
            return nil
        }
    }

    private static func commandBaseName(_ command: String) -> String {
        guard let separatorIndex = command.firstIndex(of: ":") else { return command }
        return String(command[..<separatorIndex])
    }

    private static func danmakuMessagePayload(from object: [String: Any]) -> LiveMessagePayload? {
        guard let info = object["info"] as? [Any],
              info.count > 1,
              let text = info[1] as? String,
              let normalizedText = normalizedMessageText(text)
        else { return nil }
        return LiveMessagePayload(
            text: normalizedText,
            color: color(from: info),
            mode: 1,
            fontSize: 25,
            senderName: danmakuSenderName(in: info)
                ?? senderName(in: object["data"] as? [String: Any]),
            inlineEmotes: liveDanmakuInlineEmotes(in: info, text: normalizedText)
        )
    }

    private static func superChatMessagePayload(from object: [String: Any]) -> LiveMessagePayload? {
        let data = object["data"] as? [String: Any]
        let text = firstString(
            in: data,
            keys: ["message", "message_jpn", "message_trans", "msg", "content"]
        )
        guard let text else { return nil }
        let color = firstColor(
            in: data,
            keys: ["background_bottom_color", "background_color", "message_color"],
            defaultColor: 0xFACC15
        )
        return LiveMessagePayload(
            text: text,
            color: color,
            mode: 5,
            fontSize: 25,
            senderName: senderName(in: data)
        )
    }

    private static func danmakuSenderName(in info: [Any]) -> String? {
        guard info.indices.contains(2) else { return nil }
        if let user = info[2] as? [Any],
           user.indices.contains(1),
           let name = user[1] as? String {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.isEmpty ? nil : trimmedName
        }
        return senderName(in: info[2] as? [String: Any])
    }

    private static func liveDanmakuInlineEmotes(
        in info: [Any],
        text: String
    ) -> [String: BiliInlineEmote] {
        guard let metadata = info.first as? [Any] else { return [:] }
        var emotes = [String: BiliInlineEmote]()

        if metadata.indices.contains(13),
           let rawEmote = jsonDictionary(from: metadata[13]),
           let emote = liveInlineEmote(from: rawEmote, fallbackToken: text) {
            insert(emote, token: text, into: &emotes)
        }

        guard metadata.indices.contains(15),
              let descriptor = jsonDictionary(from: metadata[15])
        else {
            return emotes
        }

        let extra = jsonDictionary(from: descriptor["extra"]) ?? descriptor
        guard let rawEmotes = extra["emots"] as? [String: Any] else {
            return emotes
        }

        for (token, rawValue) in rawEmotes {
            guard let rawEmote = jsonDictionary(from: rawValue),
                  let emote = liveInlineEmote(from: rawEmote, fallbackToken: token)
            else { continue }
            insert(emote, token: token, into: &emotes)
        }
        return emotes
    }

    private static func insert(
        _ emote: BiliInlineEmote,
        token: String,
        into emotes: inout [String: BiliInlineEmote]
    ) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { return }
        emotes[trimmedToken] = BiliInlineEmote(
            token: trimmedToken,
            url: emote.url,
            width: emote.width,
            height: emote.height
        )
    }

    private static func liveInlineEmote(
        from raw: [String: Any],
        fallbackToken: String
    ) -> BiliInlineEmote? {
        guard let url = rawString(
            in: raw,
            keys: ["url", "gif_url", "url_webp", "url_png"]
        ) else { return nil }
        let token = rawString(in: raw, keys: ["text", "emoticon_unique", "emote"]) ?? fallbackToken
        return BiliInlineEmote(
            token: token,
            url: url.normalizedBiliURL(),
            width: doubleValue(raw["width"]),
            height: doubleValue(raw["height"])
        )
    }

    private static func jsonDictionary(from value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        guard let json = value as? String,
              let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func rawString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }

    private static func interactWordPayload(from object: [String: Any]) -> LiveMessagePayload? {
        guard let data = object["data"] as? [String: Any] else { return nil }
        let senderName = senderName(in: data)
        if let text = firstString(in: data, keys: ["msg", "message", "content", "text"]) {
            return LiveMessagePayload(
                text: textWithoutLeadingSenderName(text, senderName: senderName),
                color: 0xE5E7EB,
                mode: 1,
                fontSize: 24,
                senderName: senderName
            )
        }
        guard let senderName,
              let action = interactWordAction(from: data)
        else { return nil }
        return LiveMessagePayload(
            text: action,
            color: 0xE5E7EB,
            mode: 1,
            fontSize: 24,
            senderName: senderName
        )
    }

    private static func interactWordAction(from data: [String: Any]) -> String? {
        switch intValue(data["msg_type"]) {
        case 1:
            return "进入直播间"
        case 2:
            return "关注了直播间"
        case 3:
            return "分享了直播间"
        case 4:
            return "特别关注进入直播间"
        default:
            return nil
        }
    }

    private static func entryEffectPayload(from object: [String: Any]) -> LiveMessagePayload? {
        guard let data = object["data"] as? [String: Any] else { return nil }
        guard var text = firstString(in: data, keys: ["copy_writing", "msg", "content", "text"]) else {
            return nil
        }
        let senderName = senderName(in: data)
        if senderName != nil, text.contains("<%user_name%>") {
            text = text.replacingOccurrences(of: "<%user_name%>", with: "")
        }
        guard let normalizedText = normalizedMessageText(text) else { return nil }
        return LiveMessagePayload(
            text: textWithoutLeadingSenderName(normalizedText, senderName: senderName),
            color: 0xFDE68A,
            mode: 1,
            fontSize: 24,
            senderName: senderName
        )
    }

    private static func noticeMessagePayload(from object: [String: Any]) -> LiveMessagePayload? {
        let text = firstString(
            in: object,
            keys: ["msg_common", "msg_self", "message", "msg", "content"]
        )
        guard let text else { return nil }
        return LiveMessagePayload(text: text, color: 0xFDE68A, mode: 5, fontSize: 24)
    }

    private static func giftMessagePayload(from object: [String: Any]) -> LiveMessagePayload? {
        guard let data = object["data"] as? [String: Any],
              let senderName = senderName(in: data),
              let giftName = firstString(in: data, keys: ["giftName", "gift_name", "gift"])
        else { return nil }
        let action = firstString(in: data, keys: ["action"]) ?? "送出"
        let count = max(1, intValue(data["num"]) ?? intValue(data["total_num"]) ?? intValue(data["combo_num"]) ?? 1)
        let countText = count > 1 ? "\(count) 个 " : ""
        return LiveMessagePayload(
            text: "\(action) \(countText)\(giftName)",
            color: 0xF9A8D4,
            mode: 1,
            fontSize: 24,
            senderName: senderName
        )
    }

    private static func guardBuyPayload(from object: [String: Any]) -> LiveMessagePayload? {
        guard let data = object["data"] as? [String: Any],
              let senderName = senderName(in: data)
        else { return nil }
        let guardName: String
        switch intValue(data["guard_level"]) {
        case 1:
            guardName = "总督"
        case 2:
            guardName = "提督"
        case 3:
            guardName = "舰长"
        default:
            guardName = "大航海"
        }
        return LiveMessagePayload(
            text: "开通了\(guardName)",
            color: 0xFCA5A5,
            mode: 5,
            fontSize: 24,
            senderName: senderName
        )
    }

    private static func textMessagePayload(
        from object: [String: Any],
        keys: [String],
        color: UInt32
    ) -> LiveMessagePayload? {
        guard let data = object["data"] as? [String: Any] else { return nil }
        let nestedData = data["data"] as? [String: Any]
        guard let text = firstString(in: data, keys: keys)
            ?? firstString(in: nestedData, keys: keys)
        else { return nil }
        let senderName = senderName(in: data) ?? senderName(in: nestedData)
        return LiveMessagePayload(
            text: textWithoutLeadingSenderName(text, senderName: senderName),
            color: color,
            mode: 1,
            fontSize: 24,
            senderName: senderName
        )
    }

    private static func color(from info: [Any]) -> UInt32 {
        guard let metadata = info.first as? [Any],
              metadata.count > 3
        else { return 0xFF_FF_FF }
        if let color = metadata[3] as? UInt32 {
            return color
        }
        if let color = metadata[3] as? Int, color > 0 {
            return UInt32(color)
        }
        return 0xFF_FF_FF
    }

    private static func firstString(in dictionary: [String: Any]?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            guard let value = stringValue(dictionary[key]),
                  let normalizedValue = normalizedMessageText(value)
            else { continue }
            return normalizedValue
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        return nil
    }

    private static func normalizedMessageText(_ text: String) -> String? {
        let withoutTags = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        let collapsed = withoutTags.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstColor(
        in dictionary: [String: Any]?,
        keys: [String],
        defaultColor: UInt32
    ) -> UInt32 {
        guard let dictionary else { return defaultColor }
        for key in keys {
            if let color = colorValue(dictionary[key]) {
                return color
            }
        }
        return defaultColor
    }

    private static func colorValue(_ value: Any?) -> UInt32? {
        if let value = value as? UInt32 {
            return value
        }
        if let value = value as? Int, value > 0 {
            return UInt32(value)
        }
        if let value = value as? NSNumber, value.intValue > 0 {
            return UInt32(value.intValue)
        }
        guard let value = value as? String else { return nil }
        let sanitized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !sanitized.isEmpty else { return nil }
        return UInt32(sanitized, radix: 16)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }

    private static func senderName(in dictionary: [String: Any]?) -> String? {
        guard let dictionary else { return nil }
        if let userName = firstString(in: dictionary, keys: ["uname", "user_name", "username", "name"]) {
            return userName
        }

        for key in ["user", "user_info", "userInfo", "uinfo", "base", "data"] {
            guard let nestedDictionary = dictionary[key] as? [String: Any],
                  let userName = senderName(in: nestedDictionary)
            else { continue }
            return userName
        }
        return nil
    }

    private static func textWithoutLeadingSenderName(
        _ text: String,
        senderName: String?
    ) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let senderName,
              trimmedText.hasPrefix(senderName)
        else { return trimmedText }

        let suffix = trimmedText
            .dropFirst(senderName.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":：,，-"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? trimmedText : suffix
    }

    private static func inflate(_ data: Data, algorithm: compression_algorithm) -> Data? {
        guard !data.isEmpty else { return nil }
        let inflated: Data? = data.withUnsafeBytes { sourceBuffer -> Data? in
            guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let chunkSize = 64 * 1024
            let destinationPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { destinationPointer.deallocate() }

            var stream = compression_stream(
                dst_ptr: destinationPointer,
                dst_size: chunkSize,
                src_ptr: sourcePointer,
                src_size: data.count,
                state: nil
            )
            let status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, algorithm)
            guard status != COMPRESSION_STATUS_ERROR else { return nil }
            defer { compression_stream_destroy(&stream) }

            var output = Data()
            while true {
                let status = compression_stream_process(&stream, 0)
                switch status {
                case COMPRESSION_STATUS_OK:
                    output.append(destinationPointer, count: chunkSize - stream.dst_size)
                    stream.dst_ptr = destinationPointer
                    stream.dst_size = chunkSize
                case COMPRESSION_STATUS_END:
                    output.append(destinationPointer, count: chunkSize - stream.dst_size)
                    return output
                default:
                    return nil
                }
            }
        }
        return inflated
    }
}

nonisolated private extension Data {
    mutating func appendBigEndianUInt16(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendBigEndianUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendBigEndianUInt64(_ value: UInt64) {
        append(UInt8((value >> 56) & 0xFF))
        append(UInt8((value >> 48) & 0xFF))
        append(UInt8((value >> 40) & 0xFF))
        append(UInt8((value >> 32) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}

nonisolated private extension Array where Element == UInt8 {
    func bigEndianUInt16(at index: Int) -> UInt16 {
        (UInt16(self[index]) << 8) | UInt16(self[index + 1])
    }

    func bigEndianUInt32(at index: Int) -> UInt32 {
        (UInt32(self[index]) << 24)
            | (UInt32(self[index + 1]) << 16)
            | (UInt32(self[index + 2]) << 8)
            | UInt32(self[index + 3])
    }

    func bigEndianUInt64(at index: Int) -> UInt64 {
        (UInt64(self[index]) << 56)
            | (UInt64(self[index + 1]) << 48)
            | (UInt64(self[index + 2]) << 40)
            | (UInt64(self[index + 3]) << 32)
            | (UInt64(self[index + 4]) << 24)
            | (UInt64(self[index + 5]) << 16)
            | (UInt64(self[index + 6]) << 8)
            | UInt64(self[index + 7])
    }
}
