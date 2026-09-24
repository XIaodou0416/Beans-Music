import Foundation

struct HLSMediaSegmentTransform: Sendable {
    let baseMediaDecodeTimeOffset: UInt64

    nonisolated func apply(to data: Data) -> Data {
        applyResult(to: data).data
    }

    nonisolated func applyResult(to data: Data) -> FMP4TimelineNormalizer.NormalizationResult {
        guard baseMediaDecodeTimeOffset > 0 else {
            return FMP4TimelineNormalizer.NormalizationResult(data: data, didNormalizeTiming: true)
        }
        return FMP4TimelineNormalizer.normalizedResult(
            data,
            subtractingBaseMediaDecodeTime: baseMediaDecodeTimeOffset
        )
    }
}

enum FMP4TimelineNormalizer {
    struct InitialTiming: Sendable {
        let baseMediaDecodeTimeTicks: UInt64
    }

    struct NormalizationResult: Sendable {
        let data: Data
        let didNormalizeTiming: Bool
    }

    nonisolated static func initialTiming(in data: Data) -> InitialTiming? {
        guard data.count >= 16 else { return nil }
        let bytes = [UInt8](data)
        return firstTiming(in: bytes, range: 0..<bytes.count)
    }

    nonisolated static func normalized(
        _ data: Data,
        subtractingBaseMediaDecodeTime baseMediaDecodeTimeOffset: UInt64
    ) -> Data {
        normalizedResult(
            data,
            subtractingBaseMediaDecodeTime: baseMediaDecodeTimeOffset
        ).data
    }

    nonisolated static func normalizedResult(
        _ data: Data,
        subtractingBaseMediaDecodeTime baseMediaDecodeTimeOffset: UInt64
    ) -> NormalizationResult {
        guard baseMediaDecodeTimeOffset > 0, data.count >= 16 else {
            return NormalizationResult(data: data, didNormalizeTiming: baseMediaDecodeTimeOffset == 0)
        }
        var bytes = [UInt8](data)
        let didNormalizeTiming = normalizeBoxes(
            in: &bytes,
            range: 0..<bytes.count,
            subtractingBaseMediaDecodeTime: baseMediaDecodeTimeOffset
        )
        return NormalizationResult(data: Data(bytes), didNormalizeTiming: didNormalizeTiming)
    }

    private nonisolated static func normalizeBoxes(
        in bytes: inout [UInt8],
        range: Range<Int>,
        subtractingBaseMediaDecodeTime baseMediaDecodeTimeOffset: UInt64
    ) -> Bool {
        var didNormalizeTiming = false
        var cursor = range.lowerBound
        while cursor + 8 <= range.upperBound {
            let boxStart = cursor
            let declaredSize = Int64(readUInt32(bytes, offset: cursor))
            guard cursor + 8 <= range.upperBound else { return didNormalizeTiming }
            let typeStart = cursor + 4
            let typeEnd = cursor + 8
            let type = String(bytes: bytes[typeStart..<typeEnd], encoding: .ascii)
            cursor += 8

            let boxEnd: Int
            if declaredSize == 1 {
                guard cursor + 8 <= range.upperBound else { return didNormalizeTiming }
                let largeSize = readUInt64(bytes, offset: cursor)
                cursor += 8
                guard largeSize >= 16 else { return didNormalizeTiming }
                boxEnd = boxStart + Int(min(UInt64(Int.max), largeSize))
            } else if declaredSize == 0 {
                boxEnd = range.upperBound
            } else {
                guard declaredSize >= 8 else { return didNormalizeTiming }
                boxEnd = boxStart + Int(declaredSize)
            }

            guard boxEnd <= range.upperBound, boxEnd > cursor else { return didNormalizeTiming }

            if type == "tfdt" {
                didNormalizeTiming = normalizeTFDT(
                    in: &bytes,
                    payloadStart: cursor,
                    boxEnd: boxEnd,
                    subtractingBaseMediaDecodeTime: baseMediaDecodeTimeOffset
                ) || didNormalizeTiming
            } else if isContainerBox(type) {
                didNormalizeTiming = normalizeBoxes(
                    in: &bytes,
                    range: cursor..<boxEnd,
                    subtractingBaseMediaDecodeTime: baseMediaDecodeTimeOffset
                ) || didNormalizeTiming
            }

            cursor = boxEnd
        }
        return didNormalizeTiming
    }

    private nonisolated static func firstTiming(in bytes: [UInt8], range: Range<Int>) -> InitialTiming? {
        var baseDecodeTime: UInt64?
        var cursor = range.lowerBound
        while cursor + 8 <= range.upperBound {
            let boxStart = cursor
            let declaredSize = Int64(readUInt32(bytes, offset: cursor))
            guard cursor + 8 <= range.upperBound else { return nil }
            let typeStart = cursor + 4
            let typeEnd = cursor + 8
            let type = String(bytes: bytes[typeStart..<typeEnd], encoding: .ascii)
            cursor += 8

            let boxEnd: Int
            if declaredSize == 1 {
                guard cursor + 8 <= range.upperBound else { return nil }
                let largeSize = readUInt64(bytes, offset: cursor)
                cursor += 8
                guard largeSize >= 16 else { return nil }
                boxEnd = boxStart + Int(min(UInt64(Int.max), largeSize))
            } else if declaredSize == 0 {
                boxEnd = range.upperBound
            } else {
                guard declaredSize >= 8 else { return nil }
                boxEnd = boxStart + Int(declaredSize)
            }

            guard boxEnd <= range.upperBound, boxEnd > cursor else { return nil }

            if type == "tfdt" {
                baseDecodeTime = readTFDT(in: bytes, payloadStart: cursor, boxEnd: boxEnd)
            } else if isContainerBox(type), let nested = firstTiming(in: bytes, range: cursor..<boxEnd) {
                if baseDecodeTime == nil {
                    baseDecodeTime = nested.baseMediaDecodeTimeTicks
                }
            }

            if let baseDecodeTime {
                return InitialTiming(
                    baseMediaDecodeTimeTicks: baseDecodeTime
                )
            }

            cursor = boxEnd
        }
        if let baseDecodeTime {
            return InitialTiming(
                baseMediaDecodeTimeTicks: baseDecodeTime
            )
        }
        return nil
    }

    private nonisolated static func readTFDT(in bytes: [UInt8], payloadStart: Int, boxEnd: Int) -> UInt64? {
        guard payloadStart + 8 <= boxEnd else { return nil }
        let version = bytes[payloadStart]
        let timeOffset = payloadStart + 4
        if version == 1 {
            guard timeOffset + 8 <= boxEnd else { return nil }
            return readUInt64(bytes, offset: timeOffset)
        } else {
            guard timeOffset + 4 <= boxEnd else { return nil }
            return UInt64(readUInt32(bytes, offset: timeOffset))
        }
    }

    private nonisolated static func normalizeTFDT(
        in bytes: inout [UInt8],
        payloadStart: Int,
        boxEnd: Int,
        subtractingBaseMediaDecodeTime offset: UInt64
    ) -> Bool {
        guard offset > 0 else { return true }
        guard payloadStart + 8 <= boxEnd else { return false }
        let version = bytes[payloadStart]
        let timeOffset = payloadStart + 4
        if version == 1 {
            guard timeOffset + 8 <= boxEnd else { return false }
            let original = readUInt64(bytes, offset: timeOffset)
            writeUInt64(original > offset ? original - offset : 0, to: &bytes, offset: timeOffset)
        } else {
            guard timeOffset + 4 <= boxEnd else { return false }
            let original = UInt64(readUInt32(bytes, offset: timeOffset))
            let normalized = original > offset ? original - offset : 0
            writeUInt32(UInt32(min(normalized, UInt64(UInt32.max))), to: &bytes, offset: timeOffset)
        }
        return true
    }

    private nonisolated static func isContainerBox(_ type: String?) -> Bool {
        switch type {
        case "moof", "traf", "moov", "trak", "mdia", "minf", "stbl", "edts", "dinf", "mvex":
            return true
        default:
            return false
        }
    }

    private nonisolated static func readUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private nonisolated static func readUInt64(_ bytes: [UInt8], offset: Int) -> UInt64 {
        (UInt64(readUInt32(bytes, offset: offset)) << 32) | UInt64(readUInt32(bytes, offset: offset + 4))
    }

    private nonisolated static func writeUInt32(_ value: UInt32, to bytes: inout [UInt8], offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xff)
        bytes[offset + 1] = UInt8((value >> 16) & 0xff)
        bytes[offset + 2] = UInt8((value >> 8) & 0xff)
        bytes[offset + 3] = UInt8(value & 0xff)
    }

    private nonisolated static func writeUInt64(_ value: UInt64, to bytes: inout [UInt8], offset: Int) {
        writeUInt32(UInt32((value >> 32) & 0xffff_ffff), to: &bytes, offset: offset)
        writeUInt32(UInt32(value & 0xffff_ffff), to: &bytes, offset: offset + 4)
    }
}

enum HLSProxyRoute: Sendable {
    case data(Data, contentType: String)
    case remoteByteRange(
        url: URL,
        fallbackURLs: [URL],
        range: HTTPByteRange,
        contentType: String,
        transform: HLSMediaSegmentTransform?
    )
}
