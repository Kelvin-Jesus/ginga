import CoreFoundation
import Foundation

/// A JSON value, used to compare decoded messages across implementations (§9).
public indirect enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONValue(any: JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    init(any value: Any) throws {
        switch value {
        case is NSNull:
            self = .null
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            self = .bool(number.boolValue)
        case let number as NSNumber:
            self = .number(number.doubleValue)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(try array.map(JSONValue.init(any:)))
        case let object as [String: Any]:
            self = .object(try object.mapValues(JSONValue.init(any:)))
        default:
            throw ProtocolError.malformed("unsupported JSON value \(type(of: value))")
        }
    }

    /// JSONSerialization-compatible representation (integral numbers stay integers).
    public var foundationObject: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .number(let value): value.rounded() == value && abs(value) < 9_007_199_254_740_992 ? Int64(value) as Any : value as Any
        case .string(let value): value
        case .array(let values): values.map(\.foundationObject)
        case .object(let values): values.mapValues(\.foundationObject)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let values) = self { return values[key] }
        return nil
    }
}

public struct ProtocolTestVector: Sendable {
    public var name: String
    public var description: String
    public var bytes: Data
    /// Forward-compatibility vectors: implementations only have to decode them.
    public var decodeOnly: Bool
    public var decoded: JSONValue

    /// The file contents written to `protocol/test-vectors/<name>.json`.
    public func fileData() throws -> Data {
        let object: [String: Any] = [
            "name": name,
            "description": description,
            "hex": bytes.hexString,
            "decodeOnly": decodeOnly,
            "decoded": decoded.foundationObject,
        ]
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}

public enum ProtocolTestVectors {
    /// The `decoded` descriptor of one framed message: `{type, flags, stream, fields}` (§9).
    public static func describe(_ raw: RawMessage) throws -> JSONValue {
        let message = try MessageCodec.decode(raw)
        let fields: JSONValue
        let name: String
        switch message {
        case .videoFrame(let frame):
            name = MessageType.videoFrame.name
            fields = .object([
                "frameId": .number(Double(frame.frameId)),
                "captureTimeUs": .number(Double(frame.captureTimeUs)),
                "encodeDurationUs": .number(Double(frame.encodeDurationUs)),
                "dataHex": .string(frame.data.hexString),
            ])
        case .input(let input):
            name = MessageType.input.name
            fields = .object([
                "sequence": .number(Double(input.sequence)),
                "eventTimeUs": .number(Double(input.eventTimeUs)),
                "kind": .number(Double(input.kind.rawValue)),
                "action": .number(Double(input.action.rawValue)),
                "pointers": .array(input.pointers.map { pointer in
                    .object([
                        "pointerId": .number(Double(pointer.pointerId)),
                        "toolType": .number(Double(pointer.toolType.rawValue)),
                        "buttons": .number(Double(pointer.buttons.rawValue)),
                        "x": .number(Double(pointer.x)),
                        "y": .number(Double(pointer.y)),
                        "pressure": .number(Double(pointer.pressure)),
                        "tiltX": .number(Double(pointer.tiltX)),
                        "tiltY": .number(Double(pointer.tiltY)),
                        "distance": .number(Double(pointer.distance)),
                    ])
                }),
            ])
        case .cursor(let cursor):
            name = MessageType.cursor.name
            fields = .object([
                "sequence": .number(Double(cursor.sequence)), "timeUs": .number(Double(cursor.timeUs)),
                "x": .number(Double(cursor.x)), "y": .number(Double(cursor.y)),
                "visible": .bool(cursor.visible), "shapeId": .number(Double(cursor.shapeId)),
            ])
        case .cursorShape(let shape):
            name = MessageType.cursorShape.name
            fields = .object([
                "shapeId": .number(Double(shape.shapeId)), "width": .number(Double(shape.width)), "height": .number(Double(shape.height)),
                "hotspotX": .number(Double(shape.hotspotX)), "hotspotY": .number(Double(shape.hotspotY)),
                "pngHex": .string(shape.png.hexString),
            ])
        case .key(let key):
            name = MessageType.key.name
            fields = .object([
                "sequence": .number(Double(key.sequence)), "eventTimeUs": .number(Double(key.eventTimeUs)),
                "action": .number(Double(key.action.rawValue)), "usage": .number(Double(key.usage)),
                "modifiers": .number(Double(key.modifiers.rawValue)),
            ])
        case .ping(let ping):
            name = MessageType.ping.name
            fields = .object(["id": .number(Double(ping.id)), "t1": .number(Double(ping.t1))])
        case .pong(let pong):
            name = MessageType.pong.name
            fields = .object([
                "id": .number(Double(pong.id)), "t1": .number(Double(pong.t1)),
                "t2": .number(Double(pong.t2)), "t3": .number(Double(pong.t3)),
            ])
        case .unknown(let unknown):
            name = "UNKNOWN"
            fields = .object(["rawType": .number(Double(unknown.type)), "payloadHex": .string(unknown.payload.hexString)])
        default:
            name = message.type?.name ?? "UNKNOWN"
            fields = try JSONValue.parse(raw.payload)
        }
        return .object([
            "type": .string(name),
            "flags": .number(Double(raw.flags.rawValue)),
            "stream": .number(Double(raw.stream.rawValue)),
            "fields": fields,
        ])
    }

    public static func all() throws -> [ProtocolTestVector] {
        var vectors: [ProtocolTestVector] = []
        func add(_ name: String, _ description: String, _ message: Message) throws {
            let raw = MessageCodec.encode(message)
            vectors.append(ProtocolTestVector(name: name, description: description, bytes: FrameCodec.encode(raw), decodeOnly: false, decoded: try describe(raw)))
        }
        func addRaw(_ name: String, _ description: String, _ raw: RawMessage, decodeOnly: Bool) throws {
            vectors.append(ProtocolTestVector(name: name, description: description, bytes: FrameCodec.encode(raw), decodeOnly: decodeOnly, decoded: try describe(raw)))
        }

        let display = DisplayDescription(id: 17, name: "Galaxy Tab S11", looksLike: PixelDimensions(width: 1280, height: 800), hiDPI: true, refreshRate: 60, orientation: "landscape")
        let stream = StreamDescription(codec: "hevc", width: 2560, height: 1600, fps: 60, bitrateKbps: 40000)

        try add("hello", "HELLO from a Galaxy Tab S11", .hello(Hello(
            versions: .init(min: 1, max: 1),
            app: .init(name: "Ginga for Android", version: "0.1.0"),
            device: .init(manufacturer: "samsung", model: "SM-X730", android: "16", id: "7f0c2a91d3e84b5c"),
            display: .init(widthPx: 2560, heightPx: 1600, densityDpi: 274, refreshRates: [60, 120], rotation: 0, wideColor: true),
            decoders: [
                .init(mime: "video/hevc", profiles: ["main"], maxWidth: 4096, maxHeight: 2176, maxFps: 120, lowLatency: true),
                .init(mime: "video/avc", profiles: ["high"], maxWidth: 4096, maxHeight: 2176, maxFps: 120, lowLatency: true),
            ],
            input: .init(touch: .init(maxPointers: 10), stylus: .init(pressure: true, tilt: true, hover: true, buttons: 1)),
            transport: "adb-tcp",
            features: ["clock-sync", "receiver-report"]
        )))
        try add("hello-adb-token", "HELLO over adb with the loopback token the Mac handed the app", .hello(Hello(
            versions: .init(min: 1, max: 1),
            app: .init(name: "Ginga for Android", version: "0.1.0"),
            device: .init(manufacturer: "samsung", model: "SM-X730", android: "16", id: "7f0c2a91d3e84b5c"),
            display: .init(widthPx: 2560, heightPx: 1600, densityDpi: 274, refreshRates: [60, 120], rotation: 0),
            decoders: [.init(mime: "video/hevc", profiles: ["main"], maxWidth: 4096, maxHeight: 2176, maxFps: 120, lowLatency: true)],
            input: nil, transport: "adb-tcp", features: ["clock-sync", "receiver-report", "pause"],
            loopbackToken: String(repeating: "5a", count: 32)
        )))
        try add("hello-wifi-pairing-requested", "HELLO over Wi-Fi from a tablet that has no pin for this Mac", .hello(Hello(
            versions: .init(min: 1, max: 1),
            app: .init(name: "Ginga for Android", version: "0.1.0"),
            device: .init(manufacturer: "samsung", model: "SM-X730", android: "16", id: "7f0c2a91d3e84b5c"),
            display: .init(widthPx: 2560, heightPx: 1600, densityDpi: 274, refreshRates: [60, 120], rotation: 0),
            decoders: [.init(mime: "video/hevc", profiles: ["main"], maxWidth: 4096, maxHeight: 2176, maxFps: 120, lowLatency: true)],
            input: nil, transport: "wifi-tls", features: ["clock-sync", "receiver-report", "pause", "pairing"],
            pairingRequested: true
        )))
        try add("welcome", "WELCOME with a 2560×1600 HEVC stream", .welcome(Welcome(
            version: 1, session: "b3f1c2d4", mac: .init(name: "MacBook Air", os: "26.6.2", app: "0.3.0"),
            display: display, stream: stream, features: ["clock-sync", "receiver-report"]
        )))
        try add("configure-request-portrait", "Tablet asks for portrait after rotating", .configure(Configure(request: .init(orientation: "portrait"))))
        try add("configure-announce", "Mac announces the new display and stream", .configure(Configure(
            display: DisplayDescription(id: 17, name: "Galaxy Tab S11", looksLike: PixelDimensions(width: 800, height: 1280), hiDPI: true, refreshRate: 60, orientation: "portrait"),
            stream: StreamDescription(codec: "hevc", width: 1600, height: 2560, fps: 60, bitrateKbps: 40000)
        )))
        try add("stream-format-hevc", "HEVC parameter sets (VPS, SPS, PPS) without start codes", .streamFormat(StreamFormat(
            codec: "hevc", width: 2560, height: 1600,
            parameterSets: [Data([0x40, 0x01, 0x0C, 0x01, 0xFF, 0xFF]), Data([0x42, 0x01, 0x01, 0x01, 0x60, 0x00]), Data([0x44, 0x01, 0xC1, 0x72, 0xB4, 0x62])]
        )))
        try add("receiver-report", "Periodic receiver statistics", .receiverReport(ReceiverReport(
            lastFrameId: 18234, framesReceived: 60, framesDecoded: 60, framesRendered: 59, framesDropped: 1, bytesReceived: 5_123_456,
            decodeMs: .init(p50: 6.1, p95: 9.8), endToEndMs: .init(p50: 24, p95: 31.5), decoderQueue: 0, clockOffsetUs: -1_234_567, rttUs: 850
        )))
        try add("keyframe-request", "Decoder error recovery", .keyframeRequest(KeyframeRequest(reason: "decoder-error", lastDecodedFrameId: 18230)))
        try add("error", "Version mismatch", .error(ErrorMessage(code: "incompatible-version", message: "no common protocol version")))
        try add("goodbye", "User disconnected", .goodbye(Goodbye(reason: "user")))
        try add("video-frame-keyframe", "Keyframe (KEYFRAME flag) with a tiny Annex-B access unit", .videoFrame(VideoFrame(
            frameId: 1, captureTimeUs: 1_234_567_890_123, encodeDurationUs: 5500, isKeyframe: true,
            data: Data([0x00, 0x00, 0x00, 0x01, 0x26, 0x01, 0xAF, 0x06, 0xB8, 0x63, 0xEF])
        )))
        try add("video-frame-delta", "Delta frame", .videoFrame(VideoFrame(
            frameId: 2, captureTimeUs: 1_234_567_906_790, encodeDurationUs: 5200, isKeyframe: false,
            data: Data([0x00, 0x00, 0x00, 0x01, 0x02, 0x01, 0xD0, 0x09, 0x7E])
        )))
        try add("input-touch-down", "One finger down in the centre-top", .input(InputMessage(
            sequence: 1, eventTimeUs: 987_654_321_000, kind: .touch, action: .down,
            pointers: [PointerRecord(pointerId: 0, toolType: .finger, x: 32768, y: 16384, pressure: 65535)]
        )))
        try add("input-multitouch-move", "Two-finger move (scroll)", .input(InputMessage(
            sequence: 2, eventTimeUs: 987_654_337_000, kind: .touch, action: .move,
            pointers: [
                PointerRecord(pointerId: 0, toolType: .finger, x: 30000, y: 20000, pressure: 40000),
                PointerRecord(pointerId: 1, toolType: .finger, x: 36000, y: 20100, pressure: 41000),
            ]
        )))
        try add("input-stylus-hover", "S Pen hovering with tilt", .input(InputMessage(
            sequence: 7, eventTimeUs: 987_655_000_000, kind: .stylus, action: .hoverMove,
            pointers: [PointerRecord(pointerId: 0, toolType: .stylus, x: 1000, y: 2000, pressure: 0, tiltX: 1200, tiltY: -3400, distance: 12)]
        )))
        try add("input-stylus-down-button", "S Pen touching with the side button held", .input(InputMessage(
            sequence: 8, eventTimeUs: 987_655_016_000, kind: .stylus, action: .down,
            pointers: [PointerRecord(pointerId: 0, toolType: .stylus, buttons: [.stylusPrimary], x: 1010, y: 2020, pressure: 30000, tiltX: 1100, tiltY: -3300)]
        )))
        try add("pairing-required", "Mac asks the tablet to pair (Wi-Fi, numeric comparison)", .pairing(Pairing(state: .required, name: "Kelvin's MacBook Air")))
        try add("pairing-commit", "The tablet commits to its nonce before seeing the Mac's", .pairing(Pairing(state: .commit, commitment: "052c957131b84f9b12e9519024c730dbf4fa95abac4b8d2e5b1118b2cef8ec89")))
        try add("pairing-nonce", "The Mac's nonce", .pairing(Pairing(state: .nonce, nonce: String(repeating: "33", count: 32))))
        try add("pairing-reveal", "The tablet reveals its nonce; both screens show the code", .pairing(Pairing(state: .reveal, nonce: String(repeating: "44", count: 32))))
        try add("pairing-confirmed", "The user confirmed the codes match", .pairing(Pairing(state: .confirmed)))
        try add("ping", "Clock-sync request", .ping(Ping(id: 42, t1: 1_000_000)))
        try add("pong", "Clock-sync reply", .pong(Pong(id: 42, t1: 1_000_000, t2: 5_000_123, t3: 5_000_456)))
        try add("direct-link", "The no-router key for this tablet (sent only over an authenticated session)", .directLink(DirectLink(
            keyId: "0102030405060708", key: String(repeating: "55", count: 32)
        )))
        try add("key-down", "Shift+A pressed on a keyboard cover: usage 0x04 with left shift held", .key(KeyMessage(
            sequence: 12, eventTimeUs: 5_000_900, action: .down, usage: 0x04, modifiers: [.leftShift]
        )))
        try add("cursor-position", "The pointer at the display's centre, shape 7", .cursor(CursorPosition(
            sequence: 3, timeUs: 5_000_789, x: 32768, y: 32768, visible: true, shapeId: 7
        )))
        try add("cursor-shape", "Shape 7: a 34×44 image (stream pixels) with its hotspot, PNG bytes shortened", .cursorShape(CursorShape(
            shapeId: 7, width: 34, height: 44, hotspotX: 8, hotspotY: 6, png: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])
        )))

        try addRaw("unknown-ignorable", "Unknown type 0x7E with IGNORABLE must be skipped",
                   RawMessage(type: 0x7E, flags: [.ignorable], stream: .telemetry, payload: Data("future".utf8)), decodeOnly: false)
        try addRaw("unknown-required", "Unknown type 0x7D without IGNORABLE: decoded as unknown; the session answers ERROR unsupported and keeps the connection",
                   RawMessage(type: 0x7D, flags: [], stream: .control, payload: Data("{}".utf8)), decodeOnly: false)

        var extendedVideo = ByteWriter()
        extendedVideo.u16(22)  // 4 bytes of fields from a future version
        extendedVideo.u32(3)
        extendedVideo.u64(1_234_567_923_457)
        extendedVideo.u32(5000)
        extendedVideo.bytes(Data([0xDE, 0xAD, 0xBE, 0xEF]))
        extendedVideo.bytes(Data([0x00, 0x00, 0x00, 0x01, 0x02, 0x01]))
        try addRaw("video-frame-extended-header", "Newer sender appended 4 header bytes; skip to headerLength",
                   RawMessage(type: MessageType.videoFrame.rawValue, flags: [], stream: .video, payload: extendedVideo.data), decodeOnly: true)

        var extendedInput = ByteWriter()
        extendedInput.u16(20)  // 4 extra header bytes
        extendedInput.u32(9)
        extendedInput.u64(987_655_032_000)
        extendedInput.u8(InputKind.touch.rawValue)
        extendedInput.u8(InputAction.up.rawValue)
        extendedInput.bytes(Data([0x01, 0x02, 0x03, 0x04]))
        extendedInput.u8(1)
        extendedInput.u16(22)  // 4 extra record bytes
        extendedInput.u8(0)
        extendedInput.u8(ToolType.finger.rawValue)
        extendedInput.u16(0)
        extendedInput.u16(32768)
        extendedInput.u16(16384)
        extendedInput.u16(0)
        extendedInput.i16(0)
        extendedInput.i16(0)
        extendedInput.u16(0)
        extendedInput.bytes(Data([0xCA, 0xFE, 0xBA, 0xBE]))
        try addRaw("input-extended-record", "Newer sender appended header and record fields; skip to headerLength/recordLength",
                   RawMessage(type: MessageType.input.rawValue, flags: [], stream: .input, payload: extendedInput.data), decodeOnly: true)
        return vectors
    }
}
