import Foundation

public enum ProtocolError: Error, Hashable, Sendable, CustomStringConvertible {
    case badMagic(UInt16)
    case unsupportedFramingVersion(UInt8)
    case payloadTooLarge(UInt32)
    case truncated(String)
    case malformed(String)
    case invalidJSON(message: String, reason: String)

    public var description: String {
        switch self {
        case .badMagic(let value): String(format: "bad magic 0x%04x", value)
        case .unsupportedFramingVersion(let version): "unsupported framing version \(version)"
        case .payloadTooLarge(let length): "payload of \(length) bytes exceeds \(FrameCodec.maxPayloadLength)"
        case .truncated(let detail): "truncated message: \(detail)"
        case .malformed(let detail): "malformed message: \(detail)"
        case .invalidJSON(let message, let reason): "invalid \(message) JSON: \(reason)"
        }
    }
}

/// Header flags (§2).
public struct MessageFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    /// Receivers that don't know the type may skip the message.
    public static let ignorable = MessageFlags(rawValue: 1 << 0)
    /// Video: IDR/IRAP frame.
    public static let keyframe = MessageFlags(rawValue: 1 << 1)
    /// May be dropped under backpressure.
    public static let discardable = MessageFlags(rawValue: 1 << 2)
}

/// Logical streams (§2). Unknown values are preserved.
public struct StreamID: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let control = StreamID(rawValue: 0)
    public static let video = StreamID(rawValue: 1)
    public static let input = StreamID(rawValue: 2)
    public static let cursor = StreamID(rawValue: 3)
    public static let telemetry = StreamID(rawValue: 4)
}

/// A framed message before its payload is interpreted.
public struct RawMessage: Hashable, Sendable {
    public var type: UInt8
    public var flags: MessageFlags
    public var stream: StreamID
    public var payload: Data

    public init(type: UInt8, flags: MessageFlags, stream: StreamID, payload: Data) {
        self.type = type
        self.flags = flags
        self.stream = stream
        self.payload = payload
    }
}

public enum FrameCodec {
    public static let headerSize = 12
    public static let magic: UInt16 = 0x474E  // "GN"
    public static let framingVersion: UInt8 = 1
    public static let maxPayloadLength = 16 * 1024 * 1024

    public static func encode(_ message: RawMessage) -> Data {
        var writer = ByteWriter(capacity: headerSize + message.payload.count)
        writer.u16(magic)
        writer.u8(framingVersion)
        writer.u8(message.type)
        writer.u16(message.flags.rawValue)
        writer.u16(message.stream.rawValue)
        writer.u32(UInt32(message.payload.count))
        writer.bytes(message.payload)
        return writer.data
    }
}

/// Incremental parser for stream transports: feed arbitrary chunks, pull complete messages.
public struct FrameParser: Sendable {
    private var buffer: [UInt8] = []
    private var head = 0

    public init() {}

    public var bufferedByteCount: Int { buffer.count - head }

    public mutating func append(_ data: Data) {
        buffer.append(contentsOf: data)
    }

    /// The next complete message, nil if more bytes are needed.
    public mutating func next() throws(ProtocolError) -> RawMessage? {
        guard bufferedByteCount >= FrameCodec.headerSize else { return nil }
        var header = ByteReader(Data(buffer[head..<head + FrameCodec.headerSize]), context: "header")
        let magic = try header.u16()
        guard magic == FrameCodec.magic else { throw .badMagic(magic) }
        let version = try header.u8()
        guard version == FrameCodec.framingVersion else { throw .unsupportedFramingVersion(version) }
        let type = try header.u8()
        let flags = MessageFlags(rawValue: try header.u16())
        let stream = StreamID(rawValue: try header.u16())
        let length = try header.u32()
        guard length <= FrameCodec.maxPayloadLength else { throw .payloadTooLarge(length) }
        let total = FrameCodec.headerSize + Int(length)
        guard bufferedByteCount >= total else { return nil }

        let start = head + FrameCodec.headerSize
        let payload = Data(buffer[start..<start + Int(length)])
        head += total
        compactIfNeeded()
        return RawMessage(type: type, flags: flags, stream: stream, payload: payload)
    }

    private mutating func compactIfNeeded() {
        if head == buffer.count {
            buffer.removeAll(keepingCapacity: true)
            head = 0
        } else if head > 64 * 1024, head * 2 > buffer.count {
            buffer.removeFirst(head)
            head = 0
        }
    }
}
