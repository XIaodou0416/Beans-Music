import Foundation

struct DanmakuSettings: Codable, Equatable, Sendable {
    var fontScale: Double
    var opacity: Double
    var displayArea: DanmakuDisplayArea
    var fontWeight: DanmakuFontWeightOption
    var loadFactor: Double
    var hidesInPortrait: Bool

    init(
        fontScale: Double,
        opacity: Double,
        displayArea: DanmakuDisplayArea,
        fontWeight: DanmakuFontWeightOption,
        loadFactor: Double = 1.0,
        hidesInPortrait: Bool = true
    ) {
        self.fontScale = fontScale
        self.opacity = opacity
        self.displayArea = displayArea
        self.fontWeight = fontWeight
        self.loadFactor = loadFactor
        self.hidesInPortrait = hidesInPortrait
    }

    private enum CodingKeys: String, CodingKey {
        case fontScale
        case opacity
        case displayArea
        case fontWeight
        case loadFactor
        case hidesInPortrait
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fontScale = try container.decode(Double.self, forKey: .fontScale)
        self.opacity = try container.decode(Double.self, forKey: .opacity)
        self.displayArea = try container.decode(DanmakuDisplayArea.self, forKey: .displayArea)
        self.fontWeight = try container.decode(DanmakuFontWeightOption.self, forKey: .fontWeight)
        self.loadFactor = try container.decodeIfPresent(Double.self, forKey: .loadFactor) ?? 1.0
        self.hidesInPortrait = try container.decodeIfPresent(Bool.self, forKey: .hidesInPortrait) ?? true
    }

    static let `default` = DanmakuSettings(
        fontScale: 1.0,
        opacity: 0.92,
        displayArea: .topHalf,
        fontWeight: .semibold,
        loadFactor: 1.0,
        hidesInPortrait: true
    )

    var normalized: DanmakuSettings {
        DanmakuSettings(
            fontScale: min(max(fontScale, 0.7), 1.45),
            opacity: min(max(opacity, 0.25), 1.0),
            displayArea: displayArea.normalized,
            fontWeight: fontWeight,
            loadFactor: min(max(loadFactor, 0.35), 1.0),
            hidesInPortrait: hidesInPortrait
        )
    }
}

nonisolated struct BiliInlineEmote: Hashable, Sendable {
    let token: String
    let url: String
    let width: Double?
    let height: Double?

    init(
        token: String,
        url: String,
        width: Double? = nil,
        height: Double? = nil
    ) {
        self.token = token
        self.url = url
        self.width = width
        self.height = height
    }

    var displayURL: String? {
        url.normalizedBiliURL()
    }
}

enum DanmakuDisplayArea: String, Codable, CaseIterable, Identifiable, Sendable {
    case topQuarter
    case topHalf
    case topThreeQuarters
    case center
    case full

    static let allCases: [DanmakuDisplayArea] = [
        .topQuarter,
        .topHalf,
        .topThreeQuarters,
        .full
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topQuarter:
            return "1/4屏"
        case .topHalf:
            return "1/2屏"
        case .topThreeQuarters:
            return "3/4屏"
        case .center:
            return "1/2屏"
        case .full:
            return "全屏"
        }
    }

    var normalized: DanmakuDisplayArea {
        switch self {
        case .center:
            return .topHalf
        case .topQuarter, .topHalf, .topThreeQuarters, .full:
            return self
        }
    }
}

enum DanmakuFontWeightOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            return "细体"
        case .regular:
            return "常规"
        case .medium:
            return "中等"
        case .semibold:
            return "中粗"
        case .bold:
            return "粗体"
        case .heavy:
            return "重体"
        case .black:
            return "特粗"
        }
    }
}

nonisolated struct DanmakuItem: Identifiable, Hashable, Sendable {
    let id: String
    let time: TimeInterval
    let mode: Int
    let fontSize: Double
    let color: UInt32
    let text: String
    let senderName: String?
    let inlineEmotes: [String: BiliInlineEmote]

    init(
        id: String,
        time: TimeInterval,
        mode: Int,
        fontSize: Double,
        color: UInt32,
        text: String,
        senderName: String? = nil,
        inlineEmotes: [String: BiliInlineEmote] = [:]
    ) {
        self.id = id
        self.time = time
        self.mode = mode
        self.fontSize = fontSize
        self.color = color
        self.text = text
        self.senderName = senderName
        self.inlineEmotes = inlineEmotes
    }

    nonisolated var isScrolling: Bool {
        mode == 1 || mode == 2 || mode == 3
    }

    nonisolated var isBottomAnchored: Bool {
        mode == 4
    }

    nonisolated var isTopAnchored: Bool {
        mode == 5
    }

    nonisolated var isSupported: Bool {
        isScrolling || isBottomAnchored || isTopAnchored
    }
}

nonisolated final class DanmakuXMLParser: NSObject, XMLParserDelegate {
    private let cid: Int
    private let maxItems: Int
    private var items: [DanmakuItem] = []
    private var currentAttributes: [String: String]?
    private var currentText = ""
    private var elementIndex = 0
    private var parseError: Error?

    init(cid: Int, maxItems: Int = 6_000) {
        self.cid = cid
        self.maxItems = maxItems
    }

    func parse(data: Data) throws -> [DanmakuItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? parseError ?? BiliAPIError.emptyData
        }
        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "d", items.count < maxItems else { return }
        currentAttributes = attributeDict
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentAttributes != nil else { return }
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "d", let attributes = currentAttributes else { return }
        defer {
            currentAttributes = nil
            currentText = ""
        }

        guard items.count < maxItems,
              let parameter = attributes["p"],
              let item = Self.makeItem(
                cid: cid,
                elementIndex: elementIndex,
                parameter: parameter,
                text: currentText
              )
        else {
            elementIndex += 1
            return
        }
        elementIndex += 1
        guard item.isSupported else { return }
        items.append(item)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    private static func makeItem(
        cid: Int,
        elementIndex: Int,
        parameter: String,
        text: String
    ) -> DanmakuItem? {
        let parts = parameter.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 4,
              let time = TimeInterval(String(parts[0])),
              let mode = Int(String(parts[1]))
        else { return nil }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let fontSize = Double(String(parts[2])) ?? 25
        let color = UInt32(String(parts[3])) ?? 0xFF_FF_FF
        let id: String
        if parts.count > 7, !parts[7].isEmpty {
            id = "\(cid)-\(parts[7])-\(elementIndex)"
        } else {
            id = "\(cid)-\(elementIndex)"
        }

        return DanmakuItem(
            id: id,
            time: max(0, time),
            mode: mode,
            fontSize: fontSize,
            color: color,
            text: trimmedText
        )
    }
}

nonisolated struct DanmakuSegmentProtobufParser {
    private let cid: Int
    private let segmentIndex: Int
    private let maxItems: Int

    init(cid: Int, segmentIndex: Int, maxItems: Int = 2_200) {
        self.cid = cid
        self.segmentIndex = segmentIndex
        self.maxItems = maxItems
    }

    func parse(data: Data) throws -> [DanmakuItem] {
        guard !data.isEmpty else { return [] }
        var reader = ProtobufWireReader(data: data)
        var items = [DanmakuItem]()
        var elementIndex = 0
        items.reserveCapacity(min(maxItems, 600))

        while !reader.isAtEnd, items.count < maxItems {
            let key = try reader.readVarint()
            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 0x7)
            if fieldNumber == 1, wireType == ProtobufWireType.lengthDelimited {
                let payload = try reader.readLengthDelimited()
                if let item = try parseElement(payload, elementIndex: elementIndex) {
                    items.append(item)
                }
                elementIndex += 1
            } else {
                try reader.skipField(wireType: wireType)
            }
        }

        return items
    }

    private func parseElement(_ payload: [UInt8], elementIndex: Int) throws -> DanmakuItem? {
        var reader = ProtobufWireReader(bytes: payload)
        var numericID: UInt64?
        var idString: String?
        var progressMilliseconds: UInt64?
        var mode = 1
        var fontSize = 25.0
        var color: UInt32 = 0xFF_FF_FF
        var content = ""

        while !reader.isAtEnd {
            let key = try reader.readVarint()
            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 0x7)

            switch (fieldNumber, wireType) {
            case (1, ProtobufWireType.varint):
                numericID = try reader.readVarint()
            case (2, ProtobufWireType.varint):
                progressMilliseconds = try reader.readVarint()
            case (3, ProtobufWireType.varint):
                mode = Int(try reader.readVarint())
            case (4, ProtobufWireType.varint):
                fontSize = Double(try reader.readVarint())
            case (5, ProtobufWireType.varint):
                color = UInt32(truncatingIfNeeded: try reader.readVarint())
            case (7, ProtobufWireType.lengthDelimited):
                content = try reader.readString()
            case (12, ProtobufWireType.lengthDelimited):
                idString = try reader.readString()
            default:
                try reader.skipField(wireType: wireType)
            }
        }

        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let progressMilliseconds
        else { return nil }

        let itemID: String
        if let idString, !idString.isEmpty {
            itemID = "\(cid)-seg\(segmentIndex)-\(idString)"
        } else if let numericID {
            itemID = "\(cid)-seg\(segmentIndex)-\(numericID)"
        } else {
            itemID = "\(cid)-seg\(segmentIndex)-\(elementIndex)"
        }

        let item = DanmakuItem(
            id: itemID,
            time: TimeInterval(progressMilliseconds) / 1000,
            mode: mode,
            fontSize: fontSize,
            color: color,
            text: text
        )
        return item.isSupported ? item : nil
    }
}

nonisolated private enum ProtobufWireType {
    static let varint = 0
    static let fixed64 = 1
    static let lengthDelimited = 2
    static let fixed32 = 5
}

nonisolated private struct ProtobufWireReader {
    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) {
        self.bytes = Array(data)
    }

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool {
        index >= bytes.count
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while shift < 64 {
            guard index < bytes.count else { throw BiliAPIError.emptyData }
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }

        throw BiliAPIError.emptyData
    }

    mutating func readLengthDelimited() throws -> [UInt8] {
        let length = Int(try readVarint())
        guard length >= 0, index + length <= bytes.count else {
            throw BiliAPIError.emptyData
        }
        let slice = Array(bytes[index..<index + length])
        index += length
        return slice
    }

    mutating func readString() throws -> String {
        let payload = try readLengthDelimited()
        return String(decoding: payload, as: UTF8.self)
    }

    mutating func skipField(wireType: Int) throws {
        switch wireType {
        case ProtobufWireType.varint:
            _ = try readVarint()
        case ProtobufWireType.fixed64:
            try skipBytes(8)
        case ProtobufWireType.lengthDelimited:
            let length = Int(try readVarint())
            try skipBytes(length)
        case ProtobufWireType.fixed32:
            try skipBytes(4)
        default:
            throw BiliAPIError.emptyData
        }
    }

    private mutating func skipBytes(_ count: Int) throws {
        guard count >= 0, index + count <= bytes.count else {
            throw BiliAPIError.emptyData
        }
        index += count
    }
}
