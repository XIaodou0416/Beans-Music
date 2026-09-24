import Foundation

nonisolated struct DolbyVisionInitializationNormalization: Equatable, Sendable {
    let data: Data?
    let originalSampleEntryType: String?
    let hlsSampleEntryType: String?
    let hlsBaseLayerCodec: String?

    nonisolated var didRewriteSampleEntry: Bool {
        guard let originalSampleEntryType, let hlsSampleEntryType else { return false }
        return originalSampleEntryType != hlsSampleEntryType
    }
}

nonisolated struct VideoColorInformation: Codable, Equatable, Sendable {
    let colorType: String
    let colorPrimaries: Int
    let transferCharacteristics: Int
    let matrixCoefficients: Int
    let fullRangeFlag: Bool?

    nonisolated var hlsVideoRangeAttribute: String? {
        switch transferCharacteristics {
        case 16:
            return "PQ"
        case 18:
            return "HLG"
        default:
            return nil
        }
    }

    nonisolated var diagnosticSummary: String {
        var parts = [
            colorType,
            "primaries=\(colorPrimaries)",
            "transfer=\(transferCharacteristics)",
            "matrix=\(matrixCoefficients)"
        ]
        if let fullRangeFlag {
            parts.append(fullRangeFlag ? "full" : "limited")
        }
        return parts.joined(separator: " ")
    }
}

nonisolated struct DolbyVisionCodecConfiguration: Equatable, Sendable {
    let boxType: String
    let profile: Int
    let level: Int
    let rpuPresent: Bool
    let enhancementLayerPresent: Bool
    let baseLayerPresent: Bool
    let baseLayerSignalCompatibilityID: Int

    nonisolated static func parse(from initializationData: Data?) -> DolbyVisionCodecConfiguration? {
        guard let initializationData, !initializationData.isEmpty else { return nil }
        let bytes = [UInt8](initializationData)
        guard bytes.count >= 12 else { return nil }
        for offset in 0...(bytes.count - 12) {
            guard let boxType = dolbyVisionBoxType(in: bytes, at: offset + 4),
                  let payloadRange = payloadRange(in: bytes, boxOffset: offset)
            else { continue }
            let payload = Array(bytes[payloadRange])
            if let configuration = parseRecord(payload, boxType: boxType) {
                return configuration
            }
        }
        return nil
    }

    nonisolated var decoderCodecString: String {
        "\(codecPrefix).\(Self.twoDigit(profile)).\(Self.twoDigit(level))"
    }

    nonisolated func hlsAdvertisedCodec(
        baseLayerCodec: String,
        renderingPolicy: DolbyVisionRenderingPolicy = .stored()
    ) -> String {
        let renderingPolicy = renderingPolicy.playablePolicy
        if usesNativeDolbyVisionTrack(renderingPolicy: renderingPolicy) {
            return decoderCodecString
        }
        guard advertisesBaseLayerCodecForHLS(baseLayerCodec: baseLayerCodec) else {
            return decoderCodecString
        }
        return Self.hlsBaseLayerCodec(baseLayerCodec)
    }

    nonisolated func hlsAdvertisedSupplementalCodec(
        baseLayerCodec: String,
        renderingPolicy: DolbyVisionRenderingPolicy = .stored()
    ) -> String? {
        let renderingPolicy = renderingPolicy.playablePolicy
        guard usesSupplementalCodecsAttribute(
            baseLayerCodec: baseLayerCodec,
            renderingPolicy: renderingPolicy
        ) else { return nil }
        return supplementalCodecString
    }

    nonisolated func normalizedInitializationDataForHLS(
        _ initializationData: Data?,
        renderingPolicy: DolbyVisionRenderingPolicy = .stored()
    ) -> DolbyVisionInitializationNormalization {
        let renderingPolicy = renderingPolicy.playablePolicy
        guard let initializationData, !initializationData.isEmpty else {
            return DolbyVisionInitializationNormalization(
                data: initializationData,
                originalSampleEntryType: nil,
                hlsSampleEntryType: nil,
                hlsBaseLayerCodec: nil
            )
        }
        let hlsBaseLayerCodec = usesBaseLayerCodecForHLS
            ? Self.hevcCodecString(from: initializationData)
            : nil
        var bytes = [UInt8](initializationData)
        guard let sampleEntryTypeOffset = Self.sampleEntryTypeOffset(in: bytes),
              let originalType = Self.string(in: bytes, at: sampleEntryTypeOffset),
              let hlsType = hlsSampleEntryType(for: originalType, renderingPolicy: renderingPolicy)
        else {
            return DolbyVisionInitializationNormalization(
                data: initializationData,
                originalSampleEntryType: Self.sampleEntryType(in: initializationData),
                hlsSampleEntryType: nil,
                hlsBaseLayerCodec: hlsBaseLayerCodec
            )
        }
        if hlsType != originalType {
            bytes.replaceSubrange(sampleEntryTypeOffset..<(sampleEntryTypeOffset + 4), with: Array(hlsType.utf8))
        }
        if usesCompatibleBaseLayerOnlyHLS(renderingPolicy: renderingPolicy) {
            bytes = Self.removingDolbyVisionConfigurationBoxes(from: bytes)
        }
        if usesHLGCompatibleBaseLayer {
            bytes = Self.addingHLGColorInformationIfMissing(to: bytes)
        }
        return DolbyVisionInitializationNormalization(
            data: Data(bytes),
            originalSampleEntryType: originalType,
            hlsSampleEntryType: hlsType,
            hlsBaseLayerCodec: hlsBaseLayerCodec
        )
    }

    nonisolated static func sampleEntryType(in initializationData: Data?) -> String? {
        guard let initializationData, !initializationData.isEmpty else { return nil }
        let bytes = [UInt8](initializationData)
        guard let offset = sampleEntryTypeOffset(in: bytes) else { return nil }
        return string(in: bytes, at: offset)
    }

    nonisolated var supplementalCodecString: String {
        guard let brand = hlsCompatibilityBrand else { return decoderCodecString }
        return "\(decoderCodecString)/\(brand)"
    }

    nonisolated static func hlsCompatibleBaseLayerCodec(from codec: String) -> String {
        hlsCompatibleHEVCCodec(from: codec, initializationData: nil)
    }

    nonisolated static func hlsCompatibleHEVCCodec(from codec: String, initializationData: Data?) -> String {
        if let codecFromInitialization = hevcCodecString(from: initializationData) {
            return codecFromInitialization
        }
        let baseLayerCodec = hlsBaseLayerCodec(codec)
        guard !baseLayerCodec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isDolbyVisionCodec(baseLayerCodec)
        else {
            return fallbackHLSBaseLayerCodec
        }
        return baseLayerCodec
    }

    nonisolated static func normalizedHEVCInitializationDataForHLS(_ initializationData: Data?) -> DolbyVisionInitializationNormalization {
        guard let initializationData, !initializationData.isEmpty else {
            return DolbyVisionInitializationNormalization(
                data: initializationData,
                originalSampleEntryType: nil,
                hlsSampleEntryType: nil,
                hlsBaseLayerCodec: nil
            )
        }

        let hlsBaseLayerCodec = hevcCodecString(from: initializationData)
        var bytes = [UInt8](initializationData)
        guard let sampleEntryTypeOffset = sampleEntryTypeOffset(in: bytes),
              let originalType = string(in: bytes, at: sampleEntryTypeOffset),
              let hlsType = hlsHEVCSampleEntryType(for: originalType)
        else {
            return DolbyVisionInitializationNormalization(
                data: initializationData,
                originalSampleEntryType: sampleEntryType(in: initializationData),
                hlsSampleEntryType: nil,
                hlsBaseLayerCodec: hlsBaseLayerCodec
            )
        }
        if hlsType != originalType {
            bytes.replaceSubrange(sampleEntryTypeOffset..<(sampleEntryTypeOffset + 4), with: Array(hlsType.utf8))
        }
        return DolbyVisionInitializationNormalization(
            data: Data(bytes),
            originalSampleEntryType: originalType,
            hlsSampleEntryType: hlsType,
            hlsBaseLayerCodec: hlsBaseLayerCodec
        )
    }

    nonisolated static func hevcCodecString(from initializationData: Data?) -> String? {
        guard let initializationData, !initializationData.isEmpty else { return nil }
        let bytes = [UInt8](initializationData)
        guard let payload = hevcConfigurationPayload(in: bytes),
              payload.count >= 13,
              payload[0] == 1
        else { return nil }

        let profileByte = payload[1]
        let profileSpace = Int(profileByte >> 6)
        let tierFlag = (profileByte & 0x20) != 0
        let profileIDC = Int(profileByte & 0x1f)
        let compatibilityFlags = hlsProfileCompatibilityFlags(fromHEVCRecordFlags: readUInt32(in: payload, at: 2))
        let levelIDC = Int(payload[12])
        guard profileIDC > 0, levelIDC > 0 else { return nil }

        let profileSpacePrefix: String
        switch profileSpace {
        case 1:
            profileSpacePrefix = "A"
        case 2:
            profileSpacePrefix = "B"
        case 3:
            profileSpacePrefix = "C"
        default:
            profileSpacePrefix = ""
        }

        var constraintBytes = Array(payload[6..<12])
        while constraintBytes.last == 0 {
            constraintBytes.removeLast()
        }

        var components = [
            "hvc1",
            "\(profileSpacePrefix)\(profileIDC)",
            String(compatibilityFlags, radix: 16, uppercase: true),
            "\(tierFlag ? "H" : "L")\(levelIDC)"
        ]
        components.append(contentsOf: constraintBytes.map { String(format: "%02X", $0) })
        return components.joined(separator: ".")
    }

    nonisolated static func videoColorInformation(from initializationData: Data?) -> VideoColorInformation? {
        guard let initializationData, !initializationData.isEmpty else { return nil }
        let bytes = [UInt8](initializationData)
        guard bytes.count >= 18 else { return nil }
        for offset in 0...(bytes.count - 12) {
            guard string(in: bytes, at: offset + 4) == "colr",
                  let payloadRange = payloadRange(in: bytes, boxOffset: offset),
                  let information = videoColorInformation(in: bytes, payloadRange: payloadRange)
            else { continue }
            return information
        }
        return nil
    }

    nonisolated var usesBaseLayerCodecForHLS: Bool {
        profile == 8 || (profile == 10 && baseLayerSignalCompatibilityID != 0)
    }

    nonisolated func usesSupplementalCodecsAttribute(
        renderingPolicy: DolbyVisionRenderingPolicy = .stored()
    ) -> Bool {
        let renderingPolicy = renderingPolicy.playablePolicy
        guard renderingPolicy != .metadataPassthrough else { return false }
        return usesBaseLayerCodecForHLS
            && !usesCompatibleBaseLayerOnlyHLS(renderingPolicy: renderingPolicy)
            && !usesNativeDolbyVisionTrack(renderingPolicy: renderingPolicy)
    }

    nonisolated func usesSupplementalCodecsAttribute(
        baseLayerCodec: String,
        renderingPolicy: DolbyVisionRenderingPolicy = .stored()
    ) -> Bool {
        let renderingPolicy = renderingPolicy.playablePolicy
        guard usesSupplementalCodecsAttribute(renderingPolicy: renderingPolicy) else { return false }
        return !Self.isDolbyVisionCodec(baseLayerCodec)
    }

    nonisolated func advertisesBaseLayerCodecForHLS(baseLayerCodec: String) -> Bool {
        guard usesBaseLayerCodecForHLS else { return false }
        return !Self.isDolbyVisionCodec(baseLayerCodec)
    }

    nonisolated var hlsVideoRangeAttribute: String {
        switch baseLayerSignalCompatibilityID {
        case 4:
            return "HLG"
        default:
            return "PQ"
        }
    }

    nonisolated private var codecPrefix: String {
        boxType == "dvwC" ? "dav1" : "dvh1"
    }

    nonisolated private static let fallbackHLSBaseLayerCodec = "hvc1.1.6.L120.B0"

    nonisolated private static func hlsBaseLayerCodec(_ codec: String) -> String {
        let trimmed = codec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return codec }
        let lowercased = trimmed.lowercased()
        guard lowercased == "hev1" || lowercased.hasPrefix("hev1.") else {
            return trimmed
        }
        return "hvc1" + trimmed.dropFirst(4)
    }

    nonisolated private static func isDolbyVisionCodec(_ codec: String) -> Bool {
        let lowercased = codec.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowercased == "dvh1"
            || lowercased == "dvhe"
            || lowercased.hasPrefix("dvh1.")
            || lowercased.hasPrefix("dvhe.")
    }

    nonisolated private func hlsSampleEntryType(
        for originalType: String,
        renderingPolicy: DolbyVisionRenderingPolicy
    ) -> String? {
        switch originalType {
        case "hev1", "hvc1", "dvhe", "dvh1":
            if usesNativeDolbyVisionTrack(renderingPolicy: renderingPolicy) {
                return codecPrefix
            }
            return usesBaseLayerCodecForHLS ? "hvc1" : "dvh1"
        default:
            return nil
        }
    }

    nonisolated private var usesHLGCompatibleBaseLayer: Bool {
        profile == 8 && baseLayerSignalCompatibilityID == 4
    }

    nonisolated private func usesCompatibleBaseLayerOnlyHLS(renderingPolicy: DolbyVisionRenderingPolicy) -> Bool {
        usesBaseLayerCodecForHLS && renderingPolicy == .compatibleHLG
    }

    nonisolated private func usesNativeDolbyVisionTrack(renderingPolicy: DolbyVisionRenderingPolicy) -> Bool {
        false
    }

    nonisolated private static func hlsHEVCSampleEntryType(for originalType: String) -> String? {
        switch originalType {
        case "hev1", "hvc1", "dvhe", "dvh1":
            return "hvc1"
        default:
            return nil
        }
    }

    nonisolated private var hlsCompatibilityBrand: String? {
        switch baseLayerSignalCompatibilityID {
        case 1:
            return "db1p"
        case 2:
            return "db2g"
        case 4:
            return "db4h"
        default:
            return nil
        }
    }

    nonisolated private static func parseRecord(
        _ payload: [UInt8],
        boxType: String
    ) -> DolbyVisionCodecConfiguration? {
        guard payload.count >= 4 else { return nil }
        let profile = Int(payload[2] >> 1)
        let level = Int(((payload[2] & 0x01) << 5) | (payload[3] >> 3))
        guard profile > 0, level > 0 else { return nil }
        return DolbyVisionCodecConfiguration(
            boxType: boxType,
            profile: profile,
            level: level,
            rpuPresent: (payload[3] & 0x04) != 0,
            enhancementLayerPresent: (payload[3] & 0x02) != 0,
            baseLayerPresent: (payload[3] & 0x01) != 0,
            baseLayerSignalCompatibilityID: payload.count >= 5 ? Int(payload[4] >> 4) : 0
        )
    }

    nonisolated private static func dolbyVisionBoxType(in bytes: [UInt8], at offset: Int) -> String? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        let type = String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii)
        return type == "dvcC" || type == "dvvC" || type == "dvwC" ? type : nil
    }

    nonisolated private static func removingDolbyVisionConfigurationBoxes(from bytes: [UInt8]) -> [UInt8] {
        guard let result = rebuiltBoxesRemovingDolbyVisionConfiguration(in: bytes, range: 0..<bytes.count),
              result.removed
        else { return bytes }
        return result.bytes
    }

    nonisolated private static func addingHLGColorInformationIfMissing(to bytes: [UInt8]) -> [UInt8] {
        guard videoColorInformation(from: Data(bytes)) == nil,
              let result = rebuiltBoxesAddingHLGColorInformation(in: bytes, range: 0..<bytes.count),
              result.added
        else { return bytes }
        return result.bytes
    }

    nonisolated private static func rebuiltBoxesRemovingDolbyVisionConfiguration(
        in bytes: [UInt8],
        range: Range<Int>
    ) -> (bytes: [UInt8], removed: Bool)? {
        var output = [UInt8]()
        var removed = false
        var offset = range.lowerBound
        while offset < range.upperBound {
            guard let box = boxInfo(in: bytes, at: offset, upperBound: range.upperBound) else {
                return nil
            }
            if dolbyVisionBoxType(in: bytes, at: offset + 4) != nil {
                removed = true
                offset = box.boxRange.upperBound
                continue
            }

            let rebuiltBox: [UInt8]
            let didRemoveInBox: Bool
            if box.type == "stsd" {
                guard let rebuilt = rebuiltSTSDRemovingDolbyVisionConfiguration(in: bytes, payloadRange: box.payloadRange) else {
                    return nil
                }
                rebuiltBox = makeBox(box.type, payload: rebuilt.bytes)
                didRemoveInBox = rebuilt.removed
            } else if isContainerBox(box.type) {
                guard let rebuilt = rebuiltBoxesRemovingDolbyVisionConfiguration(in: bytes, range: box.payloadRange) else {
                    return nil
                }
                rebuiltBox = makeBox(box.type, payload: rebuilt.bytes)
                didRemoveInBox = rebuilt.removed
            } else {
                rebuiltBox = Array(bytes[box.boxRange])
                didRemoveInBox = false
            }
            output += rebuiltBox
            removed = removed || didRemoveInBox
            offset = box.boxRange.upperBound
        }
        return (output, removed)
    }

    nonisolated private static func rebuiltSTSDRemovingDolbyVisionConfiguration(
        in bytes: [UInt8],
        payloadRange: Range<Int>
    ) -> (bytes: [UInt8], removed: Bool)? {
        guard payloadRange.lowerBound + 8 <= payloadRange.upperBound else { return nil }
        var output = Array(bytes[payloadRange.lowerBound..<(payloadRange.lowerBound + 8)])
        let entryCount = readUInt32(in: bytes, at: payloadRange.lowerBound + 4)
        var removed = false
        var entryOffset = payloadRange.lowerBound + 8
        for _ in 0..<entryCount {
            guard let entry = boxInfo(in: bytes, at: entryOffset, upperBound: payloadRange.upperBound) else {
                return nil
            }
            if let rebuilt = rebuiltSampleEntryRemovingDolbyVisionConfiguration(
                in: bytes,
                entryType: entry.type,
                payloadRange: entry.payloadRange
            ) {
                output += makeBox(entry.type, payload: rebuilt.bytes)
                removed = removed || rebuilt.removed
            } else {
                output += Array(bytes[entry.boxRange])
            }
            entryOffset = entry.boxRange.upperBound
        }
        guard entryOffset == payloadRange.upperBound else { return nil }
        return (output, removed)
    }

    nonisolated private static func rebuiltSampleEntryRemovingDolbyVisionConfiguration(
        in bytes: [UInt8],
        entryType: String,
        payloadRange: Range<Int>
    ) -> (bytes: [UInt8], removed: Bool)? {
        guard isVisualSampleEntry(entryType),
              payloadRange.lowerBound + 78 <= payloadRange.upperBound
        else { return nil }
        let fixedHeaderEnd = payloadRange.lowerBound + 78
        guard let rebuiltChildren = rebuiltBoxesRemovingDolbyVisionConfiguration(
            in: bytes,
            range: fixedHeaderEnd..<payloadRange.upperBound
        ) else { return nil }
        return (
            Array(bytes[payloadRange.lowerBound..<fixedHeaderEnd]) + rebuiltChildren.bytes,
            rebuiltChildren.removed
        )
    }

    nonisolated private static func rebuiltBoxesAddingHLGColorInformation(
        in bytes: [UInt8],
        range: Range<Int>
    ) -> (bytes: [UInt8], added: Bool)? {
        var output = [UInt8]()
        var added = false
        var offset = range.lowerBound
        while offset < range.upperBound {
            guard let box = boxInfo(in: bytes, at: offset, upperBound: range.upperBound) else {
                return nil
            }

            let rebuiltBox: [UInt8]
            let didAddInBox: Bool
            if box.type == "stsd" {
                guard let rebuilt = rebuiltSTSDAddingHLGColorInformation(in: bytes, payloadRange: box.payloadRange) else {
                    return nil
                }
                rebuiltBox = makeBox(box.type, payload: rebuilt.bytes)
                didAddInBox = rebuilt.added
            } else if isContainerBox(box.type) {
                guard let rebuilt = rebuiltBoxesAddingHLGColorInformation(in: bytes, range: box.payloadRange) else {
                    return nil
                }
                rebuiltBox = makeBox(box.type, payload: rebuilt.bytes)
                didAddInBox = rebuilt.added
            } else {
                rebuiltBox = Array(bytes[box.boxRange])
                didAddInBox = false
            }
            output += rebuiltBox
            added = added || didAddInBox
            offset = box.boxRange.upperBound
        }
        return (output, added)
    }

    nonisolated private static func rebuiltSTSDAddingHLGColorInformation(
        in bytes: [UInt8],
        payloadRange: Range<Int>
    ) -> (bytes: [UInt8], added: Bool)? {
        guard payloadRange.lowerBound + 8 <= payloadRange.upperBound else { return nil }
        var output = Array(bytes[payloadRange.lowerBound..<(payloadRange.lowerBound + 8)])
        let entryCount = readUInt32(in: bytes, at: payloadRange.lowerBound + 4)
        var added = false
        var entryOffset = payloadRange.lowerBound + 8
        for _ in 0..<entryCount {
            guard let entry = boxInfo(in: bytes, at: entryOffset, upperBound: payloadRange.upperBound) else {
                return nil
            }
            if !added,
               let rebuilt = rebuiltSampleEntryAddingHLGColorInformation(
                   in: bytes,
                   entryType: entry.type,
                   payloadRange: entry.payloadRange
               ) {
                output += makeBox(entry.type, payload: rebuilt.bytes)
                added = rebuilt.added
            } else {
                output += Array(bytes[entry.boxRange])
            }
            entryOffset = entry.boxRange.upperBound
        }
        guard entryOffset == payloadRange.upperBound else { return nil }
        return (output, added)
    }

    nonisolated private static func rebuiltSampleEntryAddingHLGColorInformation(
        in bytes: [UInt8],
        entryType: String,
        payloadRange: Range<Int>
    ) -> (bytes: [UInt8], added: Bool)? {
        guard isVisualSampleEntry(entryType),
              payloadRange.lowerBound + 78 <= payloadRange.upperBound
        else { return nil }
        let fixedHeaderEnd = payloadRange.lowerBound + 78
        let childRange = fixedHeaderEnd..<payloadRange.upperBound
        guard !containsBox("colr", in: bytes, range: childRange) else { return nil }
        return (
            Array(bytes[payloadRange.lowerBound..<payloadRange.upperBound]) + hlgColorInformationBox(),
            true
        )
    }

    nonisolated private static func hevcConfigurationPayload(in bytes: [UInt8]) -> [UInt8]? {
        guard bytes.count >= 12 else { return nil }
        for offset in 0...(bytes.count - 12) {
            guard string(in: bytes, at: offset + 4) == "hvcC",
                  let payloadRange = payloadRange(in: bytes, boxOffset: offset)
            else { continue }
            return Array(bytes[payloadRange])
        }
        return nil
    }

    nonisolated private static func videoColorInformation(
        in bytes: [UInt8],
        payloadRange: Range<Int>
    ) -> VideoColorInformation? {
        guard payloadRange.lowerBound + 10 <= payloadRange.upperBound,
              let colorType = string(in: bytes, at: payloadRange.lowerBound),
              colorType == "nclx" || colorType == "nclc"
        else { return nil }

        let valuesOffset = payloadRange.lowerBound + 4
        let colorPrimaries = Int(readUInt16(in: bytes, at: valuesOffset))
        let transferCharacteristics = Int(readUInt16(in: bytes, at: valuesOffset + 2))
        let matrixCoefficients = Int(readUInt16(in: bytes, at: valuesOffset + 4))
        let fullRangeFlag: Bool?
        if colorType == "nclx" {
            guard valuesOffset + 7 <= payloadRange.upperBound else { return nil }
            fullRangeFlag = (bytes[valuesOffset + 6] & 0x80) != 0
        } else {
            fullRangeFlag = nil
        }

        return VideoColorInformation(
            colorType: colorType,
            colorPrimaries: colorPrimaries,
            transferCharacteristics: transferCharacteristics,
            matrixCoefficients: matrixCoefficients,
            fullRangeFlag: fullRangeFlag
        )
    }

    nonisolated private static func sampleEntryTypeOffset(in bytes: [UInt8]) -> Int? {
        sampleEntryTypeOffset(in: bytes, range: 0..<bytes.count)
    }

    nonisolated private static func sampleEntryTypeOffset(in bytes: [UInt8], range: Range<Int>) -> Int? {
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound {
            guard let box = boxInfo(in: bytes, at: offset, upperBound: range.upperBound) else { return nil }
            if box.type == "stsd" {
                return sampleEntryTypeOffsetInSTSD(in: bytes, payloadRange: box.payloadRange)
            }
            if isContainerBox(box.type),
               let nestedOffset = sampleEntryTypeOffset(in: bytes, range: box.payloadRange) {
                return nestedOffset
            }
            offset = box.boxRange.upperBound
        }
        return nil
    }

    nonisolated private static func sampleEntryTypeOffsetInSTSD(in bytes: [UInt8], payloadRange: Range<Int>) -> Int? {
        guard payloadRange.lowerBound + 16 <= payloadRange.upperBound else { return nil }
        let entryCount = readUInt32(in: bytes, at: payloadRange.lowerBound + 4)
        guard entryCount > 0 else { return nil }
        let entryOffset = payloadRange.lowerBound + 8
        let entrySize = Int(readUInt32(in: bytes, at: entryOffset))
        guard entrySize >= 8,
              entryOffset + entrySize <= payloadRange.upperBound
        else { return nil }
        return entryOffset + 4
    }

    nonisolated private static func payloadRange(in bytes: [UInt8], boxOffset: Int) -> Range<Int>? {
        boxInfo(in: bytes, at: boxOffset, upperBound: bytes.count)?.payloadRange
    }

    nonisolated private static func boxInfo(
        in bytes: [UInt8],
        at boxOffset: Int,
        upperBound: Int
    ) -> (type: String, payloadRange: Range<Int>, boxRange: Range<Int>)? {
        guard boxOffset >= 0, boxOffset + 8 <= bytes.count else { return nil }
        guard upperBound <= bytes.count, boxOffset + 8 <= upperBound else { return nil }
        let size32 = readUInt32(in: bytes, at: boxOffset)
        let headerSize: Int
        let boxSize: Int
        if size32 == 1 {
            guard boxOffset + 16 <= bytes.count,
                  let largeSize = Int(exactly: readUInt64(in: bytes, at: boxOffset + 8))
            else { return nil }
            headerSize = 16
            boxSize = largeSize
        } else if size32 == 0 {
            headerSize = 8
            boxSize = bytes.count - boxOffset
        } else {
            headerSize = 8
            boxSize = Int(size32)
        }
        guard boxSize >= headerSize,
              boxOffset + boxSize <= upperBound,
              let type = string(in: bytes, at: boxOffset + 4)
        else { return nil }
        return (type, (boxOffset + headerSize)..<(boxOffset + boxSize), boxOffset..<(boxOffset + boxSize))
    }

    nonisolated private static func isContainerBox(_ type: String) -> Bool {
        switch type {
        case "moov", "trak", "mdia", "minf", "stbl":
            return true
        default:
            return false
        }
    }

    nonisolated private static func isVisualSampleEntry(_ type: String) -> Bool {
        switch type {
        case "avc1", "avc3", "hvc1", "hev1", "dvh1", "dvhe":
            return true
        default:
            return false
        }
    }

    nonisolated private static func containsBox(_ type: String, in bytes: [UInt8], range: Range<Int>) -> Bool {
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound {
            guard let box = boxInfo(in: bytes, at: offset, upperBound: range.upperBound) else { return false }
            if box.type == type { return true }
            offset = box.boxRange.upperBound
        }
        return false
    }

    nonisolated private static func hlgColorInformationBox() -> [UInt8] {
        makeBox(
            "colr",
            payload: Array("nclx".utf8)
                + uint16Bytes(9)
                + uint16Bytes(18)
                + uint16Bytes(9)
                + [0]
        )
    }

    nonisolated private static func makeBox(_ type: String, payload: [UInt8]) -> [UInt8] {
        let size = UInt32(payload.count + 8)
        return [
            UInt8((size >> 24) & 0xff),
            UInt8((size >> 16) & 0xff),
            UInt8((size >> 8) & 0xff),
            UInt8(size & 0xff)
        ] + Array(type.utf8) + payload
    }

    nonisolated private static func uint16Bytes(_ value: UInt16) -> [UInt8] {
        [
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
    }

    nonisolated private static func string(in bytes: [UInt8], at offset: Int) -> String? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii)
    }

    nonisolated private static func readUInt32(in bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    nonisolated private static func readUInt16(in bytes: [UInt8], at offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    nonisolated private static func readUInt64(in bytes: [UInt8], at offset: Int) -> UInt64 {
        bytes[offset..<(offset + 8)].reduce(UInt64(0)) { result, byte in
            (result << 8) | UInt64(byte)
        }
    }

    nonisolated private static func hlsProfileCompatibilityFlags(fromHEVCRecordFlags flags: UInt32) -> UInt32 {
        var source = flags
        var result: UInt32 = 0
        for _ in 0..<32 {
            result = (result << 1) | (source & 1)
            source >>= 1
        }
        return result
    }

    nonisolated private static func twoDigit(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}
