import Foundation

/// Converts between typed messages and framed `RawMessage`s.
public enum MessageCodec {
    public static func encode(_ message: Message) -> RawMessage {
        switch message {
        case .hello(let value): json(.hello, value)
        case .welcome(let value): json(.welcome, value)
        case .configure(let value): json(.configure, value)
        case .streamFormat(let value): json(.streamFormat, value)
        case .receiverReport(let value): json(.receiverReport, value)
        case .keyframeRequest(let value): json(.keyframeRequest, value)
        case .pairing(let value): json(.pairing, value, flags: [.ignorable])
        case .directLink(let value): json(.directLink, value, flags: [.ignorable])
        case .error(let value): json(.error, value)
        case .goodbye(let value): json(.goodbye, value)
        case .videoFrame(let frame): encodeVideoFrame(frame)
        case .input(let input): encodeInput(input)
        case .cursor(let cursor): encodeCursor(cursor)
        case .cursorShape(let shape): encodeCursorShape(shape)
        case .key(let key): encodeKey(key)
        case .ping(let ping): encodePing(ping)
        case .pong(let pong): encodePong(pong)
        case .unknown(let raw): raw
        }
    }

    /// Frame bytes ready for a stream transport.
    public static func frame(_ message: Message) -> Data {
        if case .videoFrame(let frame) = message { return frameVideo(frame) }
        return FrameCodec.encode(encode(message))
    }

    /// VIDEO_FRAME straight into one buffer: both headers, then the access unit, copied once.
    /// Byte-identical to `FrameCodec.encode(encode(.videoFrame(frame)))` (golden vectors).
    private static func frameVideo(_ frame: VideoFrame) -> Data {
        let payloadLength = Int(VideoFrame.headerLengthV1) + frame.data.count
        var writer = ByteWriter(capacity: FrameCodec.headerSize + payloadLength)
        writer.u16(FrameCodec.magic)
        writer.u8(FrameCodec.framingVersion)
        writer.u8(MessageType.videoFrame.rawValue)
        writer.u16((frame.isKeyframe ? MessageFlags.keyframe : []).rawValue)
        writer.u16(StreamID.video.rawValue)
        writer.u32(UInt32(payloadLength))
        writer.u16(VideoFrame.headerLengthV1)
        writer.u32(frame.frameId)
        writer.u64(frame.captureTimeUs)
        writer.u32(frame.encodeDurationUs)
        writer.bytes(frame.data)
        return writer.data
    }

    public static func decode(_ raw: RawMessage) throws(ProtocolError) -> Message {
        // Unknown types reach the session, which skips IGNORABLE ones and answers ERROR
        // "unsupported" to the rest without dropping the connection (§1).
        guard let type = MessageType(rawValue: raw.type) else { return .unknown(raw) }
        switch type {
        case .hello: return .hello(try json(Hello.self, raw, type))
        case .welcome: return .welcome(try json(Welcome.self, raw, type))
        case .configure: return .configure(try json(Configure.self, raw, type))
        case .streamFormat: return .streamFormat(try json(StreamFormat.self, raw, type))
        case .receiverReport: return .receiverReport(try json(ReceiverReport.self, raw, type))
        case .keyframeRequest: return .keyframeRequest(try json(KeyframeRequest.self, raw, type))
        case .pairing: return .pairing(try json(Pairing.self, raw, type))
        case .directLink: return .directLink(try json(DirectLink.self, raw, type))
        case .error: return .error(try json(ErrorMessage.self, raw, type))
        case .goodbye: return .goodbye(try json(Goodbye.self, raw, type))
        case .videoFrame: return .videoFrame(try decodeVideoFrame(raw))
        case .input: return .input(try decodeInput(raw))
        case .cursor: return .cursor(try decodeCursor(raw))
        case .cursorShape: return .cursorShape(try decodeCursorShape(raw))
        case .key: return .key(try decodeKey(raw))
        case .ping: return .ping(try decodePing(raw))
        case .pong: return .pong(try decodePong(raw))
        }
    }

    // MARK: JSON

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static func json<T: Encodable>(_ type: MessageType, _ value: T, flags: MessageFlags = []) -> RawMessage {
        // Encoding plain value types with JSONEncoder cannot fail.
        let payload = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return RawMessage(type: type.rawValue, flags: flags, stream: type.stream, payload: payload)
    }

    private static func json<T: Decodable>(_ type: T.Type, _ raw: RawMessage, _ messageType: MessageType) throws(ProtocolError) -> T {
        do {
            return try JSONDecoder().decode(type, from: raw.payload)
        } catch {
            throw .invalidJSON(message: messageType.name, reason: String(describing: error))
        }
    }

    // MARK: VIDEO_FRAME

    private static func encodeVideoFrame(_ frame: VideoFrame) -> RawMessage {
        var writer = ByteWriter(capacity: Int(VideoFrame.headerLengthV1) + frame.data.count)
        writer.u16(VideoFrame.headerLengthV1)
        writer.u32(frame.frameId)
        writer.u64(frame.captureTimeUs)
        writer.u32(frame.encodeDurationUs)
        writer.bytes(frame.data)
        return RawMessage(type: MessageType.videoFrame.rawValue, flags: frame.isKeyframe ? [.keyframe] : [], stream: .video, payload: writer.data)
    }

    // MARK: KEY (IGNORABLE: added after 1.0)

    private static func encodeKey(_ key: KeyMessage) -> RawMessage {
        var writer = ByteWriter(capacity: Int(KeyMessage.headerLengthV1))
        writer.u16(KeyMessage.headerLengthV1)
        writer.u32(key.sequence)
        writer.u64(key.eventTimeUs)
        writer.u8(key.action.rawValue)
        writer.u8(0)
        writer.u16(key.usage)
        writer.u16(key.modifiers.rawValue)
        return RawMessage(type: MessageType.key.rawValue, flags: [.ignorable], stream: .input, payload: writer.data)
    }

    private static func decodeKey(_ raw: RawMessage) throws(ProtocolError) -> KeyMessage {
        var reader = ByteReader(raw.payload, context: "KEY")
        let headerLength = Int(try reader.u16())
        guard headerLength >= Int(KeyMessage.headerLengthV1) else { throw .malformed("KEY headerLength \(headerLength) < 20") }
        let sequence = try reader.u32()
        let eventTimeUs = try reader.u64()
        let actionRaw = try reader.u8()
        guard let action = KeyMessage.Action(rawValue: actionRaw) else { throw .malformed("KEY action \(actionRaw)") }
        _ = try reader.u8()
        let usage = try reader.u16()
        let modifiers = KeyMessage.Modifiers(rawValue: try reader.u16())
        try reader.skip(to: headerLength)
        return KeyMessage(sequence: sequence, eventTimeUs: eventTimeUs, action: action, usage: usage, modifiers: modifiers)
    }

    // MARK: CURSOR / CURSOR_SHAPE (IGNORABLE: added after 1.0)

    private static func encodeCursor(_ cursor: CursorPosition) -> RawMessage {
        var writer = ByteWriter(capacity: Int(CursorPosition.headerLengthV1))
        writer.u16(CursorPosition.headerLengthV1)
        writer.u32(cursor.sequence)
        writer.u64(cursor.timeUs)
        writer.u16(cursor.x)
        writer.u16(cursor.y)
        writer.u8(cursor.visible ? 1 : 0)
        writer.u8(0)
        writer.u32(cursor.shapeId)
        return RawMessage(type: MessageType.cursor.rawValue, flags: [.ignorable], stream: .cursor, payload: writer.data)
    }

    private static func decodeCursor(_ raw: RawMessage) throws(ProtocolError) -> CursorPosition {
        var reader = ByteReader(raw.payload, context: "CURSOR")
        let headerLength = Int(try reader.u16())
        guard headerLength >= Int(CursorPosition.headerLengthV1) else { throw .malformed("CURSOR headerLength \(headerLength) < 24") }
        let sequence = try reader.u32()
        let timeUs = try reader.u64()
        let x = try reader.u16()
        let y = try reader.u16()
        let visible = try reader.u8() != 0
        _ = try reader.u8()
        let shapeId = try reader.u32()
        try reader.skip(to: headerLength)
        return CursorPosition(sequence: sequence, timeUs: timeUs, x: x, y: y, visible: visible, shapeId: shapeId)
    }

    private static func encodeCursorShape(_ shape: CursorShape) -> RawMessage {
        var writer = ByteWriter(capacity: Int(CursorShape.headerLengthV1) + shape.png.count)
        writer.u16(CursorShape.headerLengthV1)
        writer.u32(shape.shapeId)
        writer.u16(shape.width)
        writer.u16(shape.height)
        writer.u16(shape.hotspotX)
        writer.u16(shape.hotspotY)
        writer.bytes(shape.png)
        return RawMessage(type: MessageType.cursorShape.rawValue, flags: [.ignorable], stream: .cursor, payload: writer.data)
    }

    private static func decodeCursorShape(_ raw: RawMessage) throws(ProtocolError) -> CursorShape {
        var reader = ByteReader(raw.payload, context: "CURSOR_SHAPE")
        let headerLength = Int(try reader.u16())
        guard headerLength >= Int(CursorShape.headerLengthV1) else { throw .malformed("CURSOR_SHAPE headerLength \(headerLength) < 14") }
        let shapeId = try reader.u32()
        let width = try reader.u16()
        let height = try reader.u16()
        let hotspotX = try reader.u16()
        let hotspotY = try reader.u16()
        try reader.skip(to: headerLength)
        return CursorShape(shapeId: shapeId, width: width, height: height, hotspotX: hotspotX, hotspotY: hotspotY, png: reader.rest())
    }

    private static func decodeVideoFrame(_ raw: RawMessage) throws(ProtocolError) -> VideoFrame {
        var reader = ByteReader(raw.payload, context: "VIDEO_FRAME")
        let headerLength = Int(try reader.u16())
        guard headerLength >= Int(VideoFrame.headerLengthV1) else { throw .malformed("VIDEO_FRAME headerLength \(headerLength) < 18") }
        let frameId = try reader.u32()
        let captureTimeUs = try reader.u64()
        let encodeDurationUs = try reader.u32()
        try reader.skip(to: headerLength)
        return VideoFrame(frameId: frameId, captureTimeUs: captureTimeUs, encodeDurationUs: encodeDurationUs,
                          isKeyframe: raw.flags.contains(.keyframe), data: reader.rest())
    }

    // MARK: INPUT

    private static func encodeInput(_ input: InputMessage) -> RawMessage {
        var writer = ByteWriter(capacity: Int(InputMessage.headerLengthV1) + 1 + input.pointers.count * Int(PointerRecord.recordLengthV1))
        writer.u16(InputMessage.headerLengthV1)
        writer.u32(input.sequence)
        writer.u64(input.eventTimeUs)
        writer.u8(input.kind.rawValue)
        writer.u8(input.action.rawValue)
        writer.u8(UInt8(clamping: input.pointers.count))
        for pointer in input.pointers.prefix(Int(UInt8.max)) {
            writer.u16(PointerRecord.recordLengthV1)
            writer.u8(pointer.pointerId)
            writer.u8(pointer.toolType.rawValue)
            writer.u16(pointer.buttons.rawValue)
            writer.u16(pointer.x)
            writer.u16(pointer.y)
            writer.u16(pointer.pressure)
            writer.i16(pointer.tiltX)
            writer.i16(pointer.tiltY)
            writer.u16(pointer.distance)
        }
        return RawMessage(type: MessageType.input.rawValue, flags: [], stream: .input, payload: writer.data)
    }

    private static func decodeInput(_ raw: RawMessage) throws(ProtocolError) -> InputMessage {
        var reader = ByteReader(raw.payload, context: "INPUT")
        let headerLength = Int(try reader.u16())
        guard headerLength >= Int(InputMessage.headerLengthV1) else { throw .malformed("INPUT headerLength \(headerLength) < 16") }
        let sequence = try reader.u32()
        let eventTimeUs = try reader.u64()
        let kind = InputKind(rawValue: try reader.u8())
        let action = InputAction(rawValue: try reader.u8())
        try reader.skip(to: headerLength)
        let count = Int(try reader.u8())
        var pointers: [PointerRecord] = []
        pointers.reserveCapacity(count)
        for _ in 0..<count {
            let start = reader.offset
            let recordLength = Int(try reader.u16())
            guard recordLength >= Int(PointerRecord.recordLengthV1) else { throw .malformed("INPUT recordLength \(recordLength) < 18") }
            let pointer = PointerRecord(
                pointerId: try reader.u8(),
                toolType: ToolType(rawValue: try reader.u8()),
                buttons: PointerButtons(rawValue: try reader.u16()),
                x: try reader.u16(),
                y: try reader.u16(),
                pressure: try reader.u16(),
                tiltX: try reader.i16(),
                tiltY: try reader.i16(),
                distance: try reader.u16()
            )
            try reader.skip(to: start + recordLength)
            pointers.append(pointer)
        }
        return InputMessage(sequence: sequence, eventTimeUs: eventTimeUs, kind: kind, action: action, pointers: pointers)
    }

    // MARK: PING / PONG

    private static func encodePing(_ ping: Ping) -> RawMessage {
        var writer = ByteWriter(capacity: 12)
        writer.u32(ping.id)
        writer.u64(ping.t1)
        return RawMessage(type: MessageType.ping.rawValue, flags: [], stream: .control, payload: writer.data)
    }

    private static func decodePing(_ raw: RawMessage) throws(ProtocolError) -> Ping {
        var reader = ByteReader(raw.payload, context: "PING")
        return Ping(id: try reader.u32(), t1: try reader.u64())
    }

    private static func encodePong(_ pong: Pong) -> RawMessage {
        var writer = ByteWriter(capacity: 28)
        writer.u32(pong.id)
        writer.u64(pong.t1)
        writer.u64(pong.t2)
        writer.u64(pong.t3)
        return RawMessage(type: MessageType.pong.rawValue, flags: [], stream: .control, payload: writer.data)
    }

    private static func decodePong(_ raw: RawMessage) throws(ProtocolError) -> Pong {
        var reader = ByteReader(raw.payload, context: "PONG")
        return Pong(id: try reader.u32(), t1: try reader.u64(), t2: try reader.u64(), t3: try reader.u64())
    }
}

/// Picks the protocol version both sides support (§3.1).
public enum VersionNegotiation {
    public static let supported = Hello.VersionRange(min: 1, max: 1)

    public static func negotiate(local: Hello.VersionRange = supported, remote: Hello.VersionRange) -> Int? {
        let high = min(local.max, remote.max)
        let low = max(local.min, remote.min)
        return high >= low ? high : nil
    }
}
