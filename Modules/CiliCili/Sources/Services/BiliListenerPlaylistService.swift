import Foundation
import zlib

nonisolated enum VideoListenPlaylistSortOrder: String, CaseIterable, Identifiable, Sendable {
    case normal
    case reverse
    case random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal:
            return "正序"
        case .reverse:
            return "倒序"
        case .random:
            return "随机"
        }
    }

    var systemImage: String {
        switch self {
        case .normal:
            return "arrow.down"
        case .reverse:
            return "arrow.up"
        case .random:
            return "shuffle"
        }
    }

    var listenerValue: UInt64 {
        switch self {
        case .normal:
            return 1
        case .reverse:
            return 2
        case .random:
            return 3
        }
    }
}

nonisolated struct BiliListenerPlaylistPage: Equatable, Sendable {
    let videos: [VideoItem]
    let totalCount: Int?
    let previousToken: String?
    let nextToken: String?
    let reachedStart: Bool
    let reachedEnd: Bool
}

nonisolated enum BiliListenerPlaylistError: LocalizedError, Equatable {
    case invalidAnchor
    case missingAccessKey
    case invalidHTTPStatus(Int)
    case grpcStatus(Int, String?)
    case emptyPlaylist
    case invalidResponse
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .invalidAnchor:
            return "当前视频缺少官方播放列表所需的信息"
        case .missingAccessKey:
            return "当前播放账号没有可用的 App 登录凭据"
        case .invalidHTTPStatus(let status):
            return "官方听视频接口 HTTP \(status)"
        case .grpcStatus(let status, let message):
            let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return detail.isEmpty
                ? "官方听视频接口 gRPC \(status)"
                : "官方听视频接口 gRPC \(status)：\(detail)"
        case .emptyPlaylist:
            return "官方听视频接口没有返回其他可播放内容"
        case .invalidResponse:
            return "官方听视频接口返回了无法识别的数据"
        case .decompressionFailed:
            return "官方听视频接口返回的数据解压失败"
        }
    }

    var diagnosticReason: String {
        switch self {
        case .invalidAnchor:
            return "invalidAnchor"
        case .missingAccessKey:
            return "missingAccessKey"
        case .invalidHTTPStatus(let status):
            return "http\(status)"
        case .grpcStatus(let status, _):
            return "grpc\(status)"
        case .emptyPlaylist:
            return "emptyPlaylist"
        case .invalidResponse:
            return "invalidResponse"
        case .decompressionFailed:
            return "decompressionFailed"
        }
    }
}

nonisolated enum BiliListenerPlaylistCodec {
    static let endpointPath = "/bilibili.app.listener.v1.Listener/Playlist"

    static func encodeRequest(
        aid: Int,
        cid: Int?,
        cursor: String?,
        sortOrder: VideoListenPlaylistSortOrder,
        pageSize: Int = 20
    ) throws -> Data {
        guard aid > 0 else { throw BiliListenerPlaylistError.invalidAnchor }
        let normalizedCursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isInitialRequest = normalizedCursor?.isEmpty != false
        if isInitialRequest, (cid ?? 0) <= 0 {
            throw BiliListenerPlaylistError.invalidAnchor
        }

        var request = BiliProtoWriter()
        if isInitialRequest {
            request.appendVarint(field: 1, value: 5) // UP_ARCHIVE
        }
        request.appendVarint(field: 2, value: UInt64(aid))
        if isInitialRequest, let cid, cid > 0 {
            request.appendMessage(field: 3) { anchor in
                anchor.appendVarint(field: 1, value: 1) // UGC video
                anchor.appendVarint(field: 3, value: UInt64(aid))
                anchor.appendVarint(field: 4, value: UInt64(cid))
            }
        }
        request.appendMessage(field: 5) { playerArgs in
            playerArgs.appendVarint(field: 1, value: 80)
            playerArgs.appendVarint(field: 3, value: 4_048)
            playerArgs.appendVarint(field: 4, value: 2)
            playerArgs.appendVarint(field: 5, value: 1)
        }
        request.appendMessage(field: 7) { sortOption in
            sortOption.appendVarint(field: 1, value: sortOrder.listenerValue)
        }
        request.appendMessage(field: 8) { pagination in
            pagination.appendVarint(field: 1, value: UInt64(max(pageSize, 1)))
            if let normalizedCursor, !normalizedCursor.isEmpty {
                pagination.appendString(field: 2, value: normalizedCursor)
            }
        }
        return request.data
    }

    static func decodeResponse(_ data: Data) throws -> BiliListenerPlaylistPage {
        var reader = BiliProtoReader(data: data)
        var totalCount: Int?
        var reachedStart = false
        var reachedEnd = false
        var items = [BiliListenerDetailItem]()
        var pagination = BiliListenerPaginationReply()

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .varint):
                totalCount = Int(clamping: try reader.readVarint())
            case (2, .varint):
                reachedStart = try reader.readVarint() != 0
            case (3, .varint):
                reachedEnd = try reader.readVarint() != 0
            case (4, .lengthDelimited):
                items.append(try decodeDetailItem(reader.readLengthDelimited()))
            case (7, .lengthDelimited):
                pagination = try decodePaginationReply(reader.readLengthDelimited())
            default:
                try reader.skipField(wire: key.wire)
            }
        }

        let videos = items.compactMap(\.videoItem)
        let previousToken = reachedStart ? nil : normalizedToken(pagination.previous)
        let nextToken = reachedEnd ? nil : normalizedToken(pagination.next)
        return BiliListenerPlaylistPage(
            videos: videos,
            totalCount: totalCount,
            previousToken: previousToken,
            nextToken: nextToken,
            reachedStart: reachedStart,
            reachedEnd: reachedEnd
        )
    }

    static func frame(_ message: Data) -> Data {
        var framed = Data([0])
        framed.appendBigEndianUInt32(UInt32(clamping: message.count))
        framed.append(message)
        return framed
    }

    static func unframe(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 5 else { throw BiliListenerPlaylistError.invalidResponse }

        var index = 0
        while index + 5 <= bytes.count {
            let compressed = bytes[index]
            let length = Int(bytes[index + 1]) << 24
                | Int(bytes[index + 2]) << 16
                | Int(bytes[index + 3]) << 8
                | Int(bytes[index + 4])
            let payloadStart = index + 5
            let payloadEnd = payloadStart + length
            guard length >= 0, payloadEnd <= bytes.count else {
                throw BiliListenerPlaylistError.invalidResponse
            }
            let payload = Data(bytes[payloadStart..<payloadEnd])
            if !payload.isEmpty {
                switch compressed {
                case 0:
                    return payload
                case 1:
                    return try inflateGZIP(payload)
                default:
                    throw BiliListenerPlaylistError.invalidResponse
                }
            }
            index = payloadEnd
        }
        throw BiliListenerPlaylistError.invalidResponse
    }

    static func grpcHeaders(
        accessKey: String,
        buvid: String,
        networkClass: PlaybackEnvironment.NetworkClass,
        traceID: String
    ) -> [String: String] {
        let profile = BiliAppSigner.Profile.androidHD
        let sessionID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let build = UInt64(profile.build) ?? 2_001_100
        let resolvedBuvid = buvid.isEmpty
            ? "11111111111111111111111111111111"
            : buvid

        var device = BiliProtoWriter()
        device.appendVarint(field: 1, value: 5)
        device.appendVarint(field: 2, value: build)
        device.appendString(field: 3, value: resolvedBuvid)
        device.appendString(field: 4, value: profile.mobiApp)
        device.appendString(field: 5, value: profile.platform)
        device.appendString(field: 6, value: "android")
        device.appendString(field: 7, value: profile.channel)
        device.appendString(field: 8, value: "android")
        device.appendString(field: 9, value: "android")
        device.appendString(field: 10, value: "15")
        device.appendString(field: 13, value: profile.appVersion)

        var network = BiliProtoWriter()
        network.appendVarint(field: 1, value: listenerNetworkValue(networkClass))

        var localeID = BiliProtoWriter()
        localeID.appendString(field: 1, value: "zh")
        localeID.appendString(field: 2, value: "Hans")
        localeID.appendString(field: 3, value: "CN")
        var locale = BiliProtoWriter()
        locale.appendMessage(field: 1, data: localeID.data)
        locale.appendMessage(field: 2, data: localeID.data)
        locale.appendString(field: 4, value: "Asia/Shanghai")

        var fawkes = BiliProtoWriter()
        fawkes.appendString(field: 1, value: profile.mobiApp)
        fawkes.appendString(field: 2, value: "prod")
        fawkes.appendString(field: 3, value: sessionID)

        var metadata = BiliProtoWriter()
        metadata.appendString(field: 1, value: accessKey)
        metadata.appendString(field: 2, value: profile.mobiApp)
        metadata.appendString(field: 3, value: "android")
        metadata.appendVarint(field: 4, value: build)
        metadata.appendString(field: 5, value: profile.channel)
        metadata.appendString(field: 6, value: resolvedBuvid)
        metadata.appendString(field: 7, value: profile.platform)

        return [
            "Accept": "application/grpc",
            "Content-Type": "application/grpc",
            "authorization": "identify_v1 \(accessKey)",
            "grpc-encoding": "gzip",
            "grpc-accept-encoding": "gzip,identity",
            "gzip-accept-encoding": "gzip,identity",
            "grpc-timeout": "15S",
            "buvid": resolvedBuvid,
            "bili-http-engine": "cronet",
            "x-bili-gaia-vtoken": "",
            "x-bili-aurora-zone": "",
            "x-bili-trace-id": traceID,
            "x-bili-exps-bin": "",
            "x-bili-device-bin": device.data.base64EncodedString(),
            "x-bili-network-bin": network.data.base64EncodedString(),
            "x-bili-locale-bin": locale.data.base64EncodedString(),
            "x-bili-fawkes-req-bin": fawkes.data.base64EncodedString(),
            "x-bili-metadata-bin": metadata.data.base64EncodedString(),
        ]
    }

    private static func listenerNetworkValue(_ networkClass: PlaybackEnvironment.NetworkClass) -> UInt64 {
        switch networkClass {
        case .wifi:
            return 1
        case .cellular, .constrained:
            return 2
        case .unknown:
            return 0
        }
    }

    private static func normalizedToken(_ token: String?) -> String? {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeDetailItem(_ bytes: [UInt8]) throws -> BiliListenerDetailItem {
        var reader = BiliProtoReader(bytes: bytes)
        var result = BiliListenerDetailItem()
        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .lengthDelimited):
                result.item = try decodePlayItem(reader.readLengthDelimited())
            case (2, .lengthDelimited):
                result.archive = try decodeArchive(reader.readLengthDelimited())
            case (3, .lengthDelimited):
                result.parts.append(try decodePart(reader.readLengthDelimited()))
            case (4, .lengthDelimited):
                result.owner = try decodeOwner(reader.readLengthDelimited())
            case (8, .varint):
                result.playable = Int(clamping: try reader.readVarint())
            default:
                try reader.skipField(wire: key.wire)
            }
        }
        return result
    }

    private static func decodePlayItem(_ bytes: [UInt8]) throws -> BiliListenerPlayItem {
        var reader = BiliProtoReader(bytes: bytes)
        var result = BiliListenerPlayItem()
        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .varint):
                result.itemType = Int(clamping: try reader.readVarint())
            case (3, .varint):
                result.aid = try reader.readVarint()
            case (4, .varint):
                result.cids.append(try reader.readVarint())
            case (4, .lengthDelimited):
                var packed = BiliProtoReader(bytes: try reader.readLengthDelimited())
                while !packed.isAtEnd {
                    result.cids.append(try packed.readVarint())
                }
            default:
                try reader.skipField(wire: key.wire)
            }
        }
        return result
    }

    private static func decodeArchive(_ bytes: [UInt8]) throws -> BiliListenerArchive {
        var reader = BiliProtoReader(bytes: bytes)
        var result = BiliListenerArchive()
        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .varint):
                result.aid = try reader.readVarint()
            case (2, .lengthDelimited):
                result.title = try reader.readString()
            case (3, .lengthDelimited):
                result.cover = try reader.readString()
            case (4, .lengthDelimited):
                result.description = try reader.readString()
            case (5, .varint):
                result.duration = try reader.readVarint()
            case (8, .varint):
                result.publishTimestamp = try reader.readVarint()
            case (9, .lengthDelimited):
                result.displayedOID = try reader.readString()
            default:
                try reader.skipField(wire: key.wire)
            }
        }
        return result
    }

    private static func decodePart(_ bytes: [UInt8]) throws -> BiliListenerPart {
        var reader = BiliProtoReader(bytes: bytes)
        var result = BiliListenerPart()
        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .varint):
                result.aid = try reader.readVarint()
            case (2, .varint):
                result.cid = try reader.readVarint()
            case (3, .lengthDelimited):
                result.title = try reader.readString()
            case (4, .varint):
                result.duration = try reader.readVarint()
            case (5, .varint):
                result.page = Int(clamping: try reader.readVarint())
            default:
                try reader.skipField(wire: key.wire)
            }
        }
        return result
    }

    private static func decodeOwner(_ bytes: [UInt8]) throws -> BiliListenerOwner {
        var reader = BiliProtoReader(bytes: bytes)
        var result = BiliListenerOwner()
        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .varint):
                result.mid = try reader.readVarint()
            case (2, .lengthDelimited):
                result.name = try reader.readString()
            case (3, .lengthDelimited):
                result.avatar = try reader.readString()
            default:
                try reader.skipField(wire: key.wire)
            }
        }
        return result
    }

    private static func decodePaginationReply(_ bytes: [UInt8]) throws -> BiliListenerPaginationReply {
        var reader = BiliProtoReader(bytes: bytes)
        var result = BiliListenerPaginationReply()
        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch (key.field, key.wire) {
            case (1, .lengthDelimited):
                result.next = try reader.readString()
            case (2, .lengthDelimited):
                result.previous = try reader.readString()
            default:
                try reader.skipField(wire: key.wire)
            }
        }
        return result
    }

    private static func inflateGZIP(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        var stream = z_stream()
        let initializeStatus = inflateInit2_(
            &stream,
            15 + 32,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initializeStatus == Z_OK else {
            throw BiliListenerPlaylistError.decompressionFailed
        }
        defer { inflateEnd(&stream) }

        return try data.withUnsafeBytes { sourceBuffer in
            guard let source = sourceBuffer.bindMemory(to: Bytef.self).baseAddress else {
                throw BiliListenerPlaylistError.decompressionFailed
            }
            stream.next_in = UnsafeMutablePointer(mutating: source)
            stream.avail_in = uInt(data.count)

            let chunkSize = 32 * 1_024
            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { destination.deallocate() }
            var output = Data()

            while true {
                stream.next_out = destination
                stream.avail_out = uInt(chunkSize)
                let status = inflate(&stream, Z_NO_FLUSH)
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(destination, count: produced)
                }
                switch status {
                case Z_STREAM_END:
                    return output
                case Z_OK:
                    continue
                default:
                    throw BiliListenerPlaylistError.decompressionFailed
                }
            }
        }
    }
}

nonisolated private struct BiliListenerDetailItem {
    var item = BiliListenerPlayItem()
    var archive = BiliListenerArchive()
    var parts = [BiliListenerPart]()
    var owner = BiliListenerOwner()
    var playable = 0

    var videoItem: VideoItem? {
        let resolvedAID = archive.aid > 0 ? archive.aid : item.aid
        guard resolvedAID > 0, resolvedAID <= UInt64(Int.max) else { return nil }
        let aid = Int(resolvedAID)
        let displayedOID = archive.displayedOID.trimmingCharacters(in: .whitespacesAndNewlines)
        let bvid = displayedOID.hasPrefix("BV") || displayedOID.hasPrefix("av")
            ? displayedOID
            : "av\(aid)"
        let title = archive.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedParts = parts.compactMap { part -> VideoPage? in
            guard part.cid > 0, part.cid <= UInt64(Int.max) else { return nil }
            return VideoPage(
                cid: Int(part.cid),
                page: part.page > 0 ? part.page : nil,
                part: part.title.isEmpty ? nil : part.title,
                duration: part.duration > 0 ? Int(clamping: part.duration) : nil,
                dimension: nil
            )
        }
        let firstCID = item.cids.first ?? parts.first?.cid
        let videoOwner: VideoOwner? = {
            guard owner.mid > 0 || !owner.name.isEmpty else { return nil }
            return VideoOwner(
                mid: Int(clamping: owner.mid),
                name: owner.name.isEmpty ? "Unknown" : owner.name,
                face: owner.avatar.isEmpty ? nil : owner.avatar
            )
        }()
        return VideoItem(
            bvid: bvid,
            aid: aid,
            title: title.isEmpty ? "视频 \(aid)" : title,
            pic: archive.cover.isEmpty ? nil : archive.cover,
            desc: archive.description.isEmpty ? nil : archive.description,
            duration: archive.duration > 0 ? Int(clamping: archive.duration) : nil,
            pubdate: archive.publishTimestamp > 0 ? Int(clamping: archive.publishTimestamp) : nil,
            owner: videoOwner,
            stat: nil,
            cid: firstCID.flatMap { $0 > 0 ? Int(clamping: $0) : nil },
            pages: resolvedParts.isEmpty ? nil : resolvedParts,
            dimension: nil
        )
    }
}

nonisolated private struct BiliListenerPlayItem {
    var itemType = 0
    var aid: UInt64 = 0
    var cids = [UInt64]()
}

nonisolated private struct BiliListenerArchive {
    var aid: UInt64 = 0
    var title = ""
    var cover = ""
    var description = ""
    var duration: UInt64 = 0
    var publishTimestamp: UInt64 = 0
    var displayedOID = ""
}

nonisolated private struct BiliListenerPart {
    var aid: UInt64 = 0
    var cid: UInt64 = 0
    var title = ""
    var duration: UInt64 = 0
    var page = 0
}

nonisolated private struct BiliListenerOwner {
    var mid: UInt64 = 0
    var name = ""
    var avatar = ""
}

nonisolated private struct BiliListenerPaginationReply {
    var next: String?
    var previous: String?
}

nonisolated private enum BiliProtoWire: Int {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

nonisolated private struct BiliProtoWriter {
    private(set) var data = Data()

    mutating func appendVarint(field: Int, value: UInt64) {
        appendRawVarint(UInt64(field << 3) | UInt64(BiliProtoWire.varint.rawValue))
        appendRawVarint(value)
    }

    mutating func appendString(field: Int, value: String) {
        appendMessage(field: field, data: Data(value.utf8))
    }

    mutating func appendMessage(field: Int, data: Data) {
        appendRawVarint(UInt64(field << 3) | UInt64(BiliProtoWire.lengthDelimited.rawValue))
        appendRawVarint(UInt64(data.count))
        self.data.append(data)
    }

    mutating func appendMessage(field: Int, build: (inout BiliProtoWriter) -> Void) {
        var nested = BiliProtoWriter()
        build(&nested)
        appendMessage(field: field, data: nested.data)
    }

    private mutating func appendRawVarint(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            data.append(UInt8(value & 0x7F) | 0x80)
            value >>= 7
        }
        data.append(UInt8(value))
    }
}

nonisolated private struct BiliProtoReader {
    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) {
        bytes = [UInt8](data)
    }

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { index >= bytes.count }

    mutating func readKey() throws -> (field: Int, wire: BiliProtoWire) {
        let rawKey = try readVarint()
        guard let wire = BiliProtoWire(rawValue: Int(rawKey & 0x7)) else {
            throw BiliListenerPlaylistError.invalidResponse
        }
        let field = Int(rawKey >> 3)
        guard field > 0 else { throw BiliListenerPlaylistError.invalidResponse }
        return (field, wire)
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while shift < 64 {
            guard index < bytes.count else { throw BiliListenerPlaylistError.invalidResponse }
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }
        throw BiliListenerPlaylistError.invalidResponse
    }

    mutating func readLengthDelimited() throws -> [UInt8] {
        let rawLength = try readVarint()
        guard rawLength <= UInt64(Int.max) else {
            throw BiliListenerPlaylistError.invalidResponse
        }
        let length = Int(rawLength)
        guard length >= 0, index + length <= bytes.count else {
            throw BiliListenerPlaylistError.invalidResponse
        }
        let payload = Array(bytes[index..<index + length])
        index += length
        return payload
    }

    mutating func readString() throws -> String {
        String(decoding: try readLengthDelimited(), as: UTF8.self)
    }

    mutating func skipField(wire: BiliProtoWire) throws {
        switch wire {
        case .varint:
            _ = try readVarint()
        case .fixed64:
            try skip(8)
        case .lengthDelimited:
            let rawLength = try readVarint()
            guard rawLength <= UInt64(Int.max) else {
                throw BiliListenerPlaylistError.invalidResponse
            }
            try skip(Int(rawLength))
        case .fixed32:
            try skip(4)
        }
    }

    private mutating func skip(_ count: Int) throws {
        guard count >= 0, index + count <= bytes.count else {
            throw BiliListenerPlaylistError.invalidResponse
        }
        index += count
    }
}

nonisolated private extension Data {
    mutating func appendBigEndianUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
