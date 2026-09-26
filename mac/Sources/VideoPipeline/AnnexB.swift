import CoreMedia
import Foundation

public enum VideoCodec: String, Codable, Sendable, CaseIterable {
    case hevc
    case h264

    public var codecType: CMVideoCodecType {
        switch self {
        case .hevc: kCMVideoCodecType_HEVC
        case .h264: kCMVideoCodecType_H264
        }
    }

    /// Android MediaCodec MIME type.
    public var mimeType: String {
        switch self {
        case .hevc: "video/hevc"
        case .h264: "video/avc"
        }
    }

    /// NAL unit type of a unit's first header byte.
    public func nalType(_ firstByte: UInt8) -> UInt8 {
        switch self {
        case .hevc: (firstByte >> 1) & 0x3F
        case .h264: firstByte & 0x1F
        }
    }

    /// VPS/SPS/PPS (HEVC) or SPS/PPS (H.264).
    public func isParameterSet(_ firstByte: UInt8) -> Bool {
        let type = nalType(firstByte)
        switch self {
        case .hevc: return (32...34).contains(type)
        case .h264: return type == 7 || type == 8
        }
    }
}

/// Conversions between the length-prefixed NAL format VideoToolbox uses and the Annex‑B byte
/// stream the protocol carries (start codes, as Android MediaCodec expects).
public enum AnnexB {
    public static let startCode = Data([0x00, 0x00, 0x00, 0x01])

    public enum ConversionError: Error, Equatable {
        case truncatedNAL(offset: Int)
        case invalidLengthSize(Int)
    }

    /// Length-prefixed NAL units (AVCC/HVCC) → Annex‑B.
    public static func fromLengthPrefixed(_ data: Data, lengthSize: Int = 4) throws -> Data {
        try nalUnits(lengthPrefixed: data, lengthSize: lengthSize).reduce(into: Data(capacity: data.count + 16)) { result, nal in
            result.append(startCode)
            result.append(nal)
        }
    }

    /// 4-byte length-prefixed units → Annex‑B **in place**: each length becomes a 4-byte start
    /// code of the same size, so the encoder's output is converted without a copy. Returns the
    /// offset of each unit's first byte (its NAL header).
    @discardableResult
    public static func convertLengthPrefixedInPlace(_ data: inout Data) throws(ConversionError) -> [Int] {
        var failure: ConversionError?
        let starts = data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> [Int] in
            var starts: [Int] = []
            var offset = 0
            while offset < buffer.count {
                guard offset + 4 <= buffer.count else {
                    failure = .truncatedNAL(offset: offset)
                    return starts
                }
                let length = Int(buffer[offset]) << 24 | Int(buffer[offset + 1]) << 16 | Int(buffer[offset + 2]) << 8 | Int(buffer[offset + 3])
                guard offset + 4 + length <= buffer.count else {
                    failure = .truncatedNAL(offset: offset + 4)
                    return starts
                }
                buffer[offset] = 0
                buffer[offset + 1] = 0
                buffer[offset + 2] = 0
                buffer[offset + 3] = 1
                starts.append(offset + 4)
                offset += 4 + length
            }
            return starts
        }
        if let failure { throw failure }
        return starts
    }

    public static func nalUnits(lengthPrefixed data: Data, lengthSize: Int = 4) throws -> [Data] {
        guard (1...4).contains(lengthSize) else { throw ConversionError.invalidLengthSize(lengthSize) }
        let bytes = [UInt8](data)
        var units: [Data] = []
        var offset = 0
        while offset < bytes.count {
            guard offset + lengthSize <= bytes.count else { throw ConversionError.truncatedNAL(offset: offset) }
            var length = 0
            for index in offset..<offset + lengthSize { length = length << 8 | Int(bytes[index]) }
            offset += lengthSize
            guard offset + length <= bytes.count else { throw ConversionError.truncatedNAL(offset: offset) }
            units.append(Data(bytes[offset..<offset + length]))
            offset += length
        }
        return units
    }

    /// NAL units → Annex‑B.
    public static func join(_ units: [Data]) -> Data {
        units.reduce(into: Data()) { result, nal in
            result.append(startCode)
            result.append(nal)
        }
    }

    /// Annex‑B → NAL units (accepts 3- and 4-byte start codes).
    public static func split(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [(codeStart: Int, payloadStart: Int)] = []
        var index = 0
        while index + 3 <= bytes.count {
            if bytes[index] == 0, bytes[index + 1] == 0 {
                if bytes[index + 2] == 1 {
                    starts.append((index, index + 3))
                    index += 3
                    continue
                }
                if index + 4 <= bytes.count, bytes[index + 2] == 0, bytes[index + 3] == 1 {
                    starts.append((index, index + 4))
                    index += 4
                    continue
                }
            }
            index += 1
        }
        return starts.enumerated().map { position, start in
            let end = position + 1 < starts.count ? starts[position + 1].codeStart : bytes.count
            return Data(bytes[start.payloadStart..<end])
        }
    }

    /// Annex‑B → 4-byte length-prefixed (what VTDecompressionSession consumes).
    public static func toLengthPrefixed(_ units: [Data]) -> Data {
        units.reduce(into: Data()) { result, nal in
            var length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
            result.append(nal)
        }
    }

    /// Parameter sets carried by a video format description, in order (VPS, SPS, PPS for HEVC).
    public static func parameterSets(of format: CMFormatDescription, codec: VideoCodec) -> [Data] {
        var count = 0
        var status: OSStatus
        switch codec {
        case .hevc:
            status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
        case .h264:
            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
        }
        guard status == noErr else { return [] }
        return (0..<count).compactMap { index in
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            switch codec {
            case .hevc:
                status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &pointer, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            case .h264:
                status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &pointer, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            }
            guard status == noErr, let pointer else { return nil }
            return Data(bytes: pointer, count: size)
        }
    }
}
