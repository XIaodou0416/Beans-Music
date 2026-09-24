import Foundation

struct SIDXParser {
    struct Reference {
        let range: HTTPByteRange
        let duration: TimeInterval
        let startTime: TimeInterval
        let startTimeTicks: UInt64
        let timescale: UInt32
    }

    nonisolated static func parseReferences(from data: Data, sidxStartOffset: Int64) throws -> [Reference] {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { throw PlayerEngineError.unsupportedMedia }

        var offset = 0
        if String(bytes: bytes[4..<min(8, bytes.count)], encoding: .ascii) != "sidx" {
            while offset + 8 <= bytes.count {
                let size = Int(readUInt32(bytes, offset: offset))
                guard size >= 8, offset + size <= bytes.count else { break }
                let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii)
                if type == "sidx" {
                    break
                }
                offset += size
            }
        }

        guard offset + 12 <= bytes.count,
              String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) == "sidx"
        else {
            throw PlayerEngineError.unsupportedMedia
        }

        let boxSize = Int64(readUInt32(bytes, offset: offset))
        let version = bytes[offset + 8]
        var cursor = offset + 12
        guard cursor + 8 <= bytes.count else { throw PlayerEngineError.unsupportedMedia }
        cursor += 4
        let timescaleValue = readUInt32(bytes, offset: cursor)
        let timescale = Double(timescaleValue)
        cursor += 4
        guard timescale > 0 else { throw PlayerEngineError.unsupportedMedia }

        let firstOffset: Int64
        let earliestPresentationTime: UInt64
        if version == 0 {
            guard cursor + 8 <= bytes.count else { throw PlayerEngineError.unsupportedMedia }
            earliestPresentationTime = UInt64(readUInt32(bytes, offset: cursor))
            cursor += 4
            firstOffset = Int64(readUInt32(bytes, offset: cursor))
            cursor += 4
        } else {
            guard cursor + 16 <= bytes.count else { throw PlayerEngineError.unsupportedMedia }
            earliestPresentationTime = readUInt64(bytes, offset: cursor)
            cursor += 8
            firstOffset = Int64(readUInt64(bytes, offset: cursor))
            cursor += 8
        }

        cursor += 2
        guard cursor + 2 <= bytes.count else { throw PlayerEngineError.unsupportedMedia }
        let referenceCount = Int(readUInt16(bytes, offset: cursor))
        cursor += 2

        var mediaOffset = sidxStartOffset + boxSize + firstOffset
        var presentationTime = TimeInterval(earliestPresentationTime) / timescale
        var elapsedTicks: UInt64 = 0
        var references = [Reference]()
        references.reserveCapacity(referenceCount)

        for _ in 0..<referenceCount {
            guard cursor + 12 <= bytes.count else { break }
            let typeAndSize = readUInt32(bytes, offset: cursor)
            cursor += 4
            let isSubsegment = (typeAndSize & 0x8000_0000) != 0
            let size = Int64(typeAndSize & 0x7fff_ffff)
            let durationOffset = cursor
            let durationTicks = readUInt32(bytes, offset: durationOffset)
            let duration = TimeInterval(durationTicks) / timescale
            cursor += 4
            cursor += 4
            guard !isSubsegment, size > 0 else { continue }
            references.append(Reference(
                range: HTTPByteRange(start: mediaOffset, endInclusive: mediaOffset + size - 1),
                duration: duration,
                startTime: presentationTime,
                startTimeTicks: earliestPresentationTime + elapsedTicks,
                timescale: timescaleValue
            ))
            mediaOffset += size
            elapsedTicks += UInt64(durationTicks)
            presentationTime += duration
        }

        return references
    }

    private nonisolated static func readUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private nonisolated static func readUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private nonisolated static func readUInt64(_ bytes: [UInt8], offset: Int) -> UInt64 {
        (UInt64(readUInt32(bytes, offset: offset)) << 32)
            | UInt64(readUInt32(bytes, offset: offset + 4))
    }
}
