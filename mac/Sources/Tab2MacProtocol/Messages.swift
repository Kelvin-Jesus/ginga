import Foundation

/// Message types (§3).
public enum MessageType: UInt8, CaseIterable, Sendable {
    case hello = 0x01
    case welcome = 0x02
    case configure = 0x03
    case streamFormat = 0x04
    case receiverReport = 0x05
    case keyframeRequest = 0x06
    /// Wi‑Fi pairing (M7); sent with IGNORABLE, only to peers that advertise "pairing".
    case pairing = 0x07
    case directLink = 0x08
    case error = 0x0E
    case goodbye = 0x0F
    case videoFrame = 0x10
    case input = 0x11
    case cursor = 0x12
    case cursorShape = 0x13
    case key = 0x14
    case ping = 0x20
    case pong = 0x21

    public var name: String {
        switch self {
        case .hello: "HELLO"
        case .welcome: "WELCOME"
        case .configure: "CONFIGURE"
        case .streamFormat: "STREAM_FORMAT"
        case .receiverReport: "RECEIVER_REPORT"
        case .keyframeRequest: "KEYFRAME_REQUEST"
        case .pairing: "PAIRING"
        case .directLink: "DIRECT_LINK"
        case .error: "ERROR"
        case .goodbye: "GOODBYE"
        case .videoFrame: "VIDEO_FRAME"
        case .input: "INPUT"
        case .cursor: "CURSOR"
        case .cursorShape: "CURSOR_SHAPE"
        case .key: "KEY"
        case .ping: "PING"
        case .pong: "PONG"
        }
    }

    public var stream: StreamID {
        switch self {
        case .hello, .welcome, .configure, .pairing, .directLink, .error, .goodbye, .ping, .pong: .control
        case .streamFormat, .keyframeRequest, .videoFrame: .video
        case .input, .key: .input
        case .cursor, .cursorShape: .cursor
        case .receiverReport: .telemetry
        }
    }

    public var isJSON: Bool {
        switch self {
        case .videoFrame, .input, .cursor, .cursorShape, .key, .ping, .pong: false
        default: true
        }
    }
}

public enum Message: Hashable, Sendable {
    case hello(Hello)
    case welcome(Welcome)
    case configure(Configure)
    case streamFormat(StreamFormat)
    case receiverReport(ReceiverReport)
    case keyframeRequest(KeyframeRequest)
    case pairing(Pairing)
    case directLink(DirectLink)
    case error(ErrorMessage)
    case goodbye(Goodbye)
    case videoFrame(VideoFrame)
    case input(InputMessage)
    case cursor(CursorPosition)
    case cursorShape(CursorShape)
    case key(KeyMessage)
    case ping(Ping)
    case pong(Pong)
    /// A type this implementation doesn't know. The session skips it when IGNORABLE and answers
    /// ERROR "unsupported" otherwise (§1).
    case unknown(RawMessage)

    public var type: MessageType? {
        switch self {
        case .hello: .hello
        case .welcome: .welcome
        case .configure: .configure
        case .streamFormat: .streamFormat
        case .receiverReport: .receiverReport
        case .keyframeRequest: .keyframeRequest
        case .pairing: .pairing
        case .directLink: .directLink
        case .error: .error
        case .goodbye: .goodbye
        case .videoFrame: .videoFrame
        case .input: .input
        case .cursor: .cursor
        case .cursorShape: .cursorShape
        case .key: .key
        case .ping: .ping
        case .pong: .pong
        case .unknown: nil
        }
    }
}

// MARK: - JSON control messages (§3.1)

public struct PixelDimensions: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct Hello: Codable, Hashable, Sendable {
    public struct VersionRange: Codable, Hashable, Sendable {
        public var min: Int
        public var max: Int
        public init(min: Int, max: Int) { self.min = min; self.max = max }
    }

    public struct App: Codable, Hashable, Sendable {
        public var name: String
        public var version: String
        public init(name: String, version: String) { self.name = name; self.version = version }
    }

    public struct Device: Codable, Hashable, Sendable {
        public var manufacturer: String
        public var model: String
        public var android: String
        /// Stable, app-scoped random ID; the Mac derives the virtual display serial from it.
        public var id: String
        public init(manufacturer: String, model: String, android: String, id: String) {
            self.manufacturer = manufacturer
            self.model = model
            self.android = android
            self.id = id
        }
    }

    public struct Display: Codable, Hashable, Sendable {
        public var widthPx: Int
        public var heightPx: Int
        public var densityDpi: Int
        public var refreshRates: [Double]
        public var rotation: Int
        public var wideColor: Bool?
        public init(widthPx: Int, heightPx: Int, densityDpi: Int, refreshRates: [Double], rotation: Int, wideColor: Bool? = nil) {
            self.widthPx = widthPx
            self.heightPx = heightPx
            self.densityDpi = densityDpi
            self.refreshRates = refreshRates
            self.rotation = rotation
            self.wideColor = wideColor
        }
    }

    public struct Decoder: Codable, Hashable, Sendable {
        public var mime: String
        public var profiles: [String]
        public var maxWidth: Int
        public var maxHeight: Int
        public var maxFps: Double
        public var lowLatency: Bool
        public init(mime: String, profiles: [String], maxWidth: Int, maxHeight: Int, maxFps: Double, lowLatency: Bool) {
            self.mime = mime
            self.profiles = profiles
            self.maxWidth = maxWidth
            self.maxHeight = maxHeight
            self.maxFps = maxFps
            self.lowLatency = lowLatency
        }
    }

    public struct Input: Codable, Hashable, Sendable {
        public struct Touch: Codable, Hashable, Sendable {
            public var maxPointers: Int
            public init(maxPointers: Int) { self.maxPointers = maxPointers }
        }

        public struct Stylus: Codable, Hashable, Sendable {
            public var pressure: Bool
            public var tilt: Bool
            public var hover: Bool
            public var buttons: Int
            public init(pressure: Bool, tilt: Bool, hover: Bool, buttons: Int) {
                self.pressure = pressure
                self.tilt = tilt
                self.hover = hover
                self.buttons = buttons
            }
        }

        public var touch: Touch?
        public var stylus: Stylus?
        public init(touch: Touch?, stylus: Stylus?) { self.touch = touch; self.stylus = stylus }
    }

    public struct Resume: Codable, Hashable, Sendable {
        public var session: String
        public init(session: String) { self.session = session }
    }

    public var versions: VersionRange
    public var app: App
    public var device: Device
    public var display: Display
    public var decoders: [Decoder]
    public var input: Input?
    public var transport: String?
    public var features: [String]?
    public var resume: Resume?
    /// `adb-tcp` only: the token the Mac handed the tablet over adb (PROTOCOL.md §5), proving the
    /// connection comes from the Tab2Mac app and not from another process on either device.
    public var loopbackToken: String?
    /// `wifi-tls` only: the tablet has no pin for the certificate this Mac presented (it forgot
    /// the Mac, or the Mac's identity changed), so it asks to pair even if the Mac knows it.
    public var pairingRequested: Bool?

    enum CodingKeys: String, CodingKey {
        case versions = "protocol"
        case app, device, display, decoders, input, transport, features, resume, loopbackToken, pairingRequested
    }

    public init(
        versions: VersionRange, app: App, device: Device, display: Display, decoders: [Decoder],
        input: Input?, transport: String?, features: [String]?, resume: Resume? = nil, loopbackToken: String? = nil,
        pairingRequested: Bool? = nil
    ) {
        self.loopbackToken = loopbackToken
        self.pairingRequested = pairingRequested
        self.versions = versions
        self.app = app
        self.device = device
        self.display = display
        self.decoders = decoders
        self.input = input
        self.transport = transport
        self.features = features
        self.resume = resume
    }
}

public struct DisplayDescription: Codable, Hashable, Sendable {
    public var id: UInt32
    public var name: String
    public var looksLike: PixelDimensions
    public var hiDPI: Bool
    public var refreshRate: Double
    public var orientation: String

    public init(id: UInt32, name: String, looksLike: PixelDimensions, hiDPI: Bool, refreshRate: Double, orientation: String) {
        self.id = id
        self.name = name
        self.looksLike = looksLike
        self.hiDPI = hiDPI
        self.refreshRate = refreshRate
        self.orientation = orientation
    }
}

public struct StreamDescription: Codable, Hashable, Sendable {
    public var codec: String
    public var width: Int
    public var height: Int
    public var fps: Double
    public var bitrateKbps: Int
    public var primaries: String
    public var transfer: String
    public var matrix: String
    public var range: String

    public init(codec: String, width: Int, height: Int, fps: Double, bitrateKbps: Int,
                primaries: String = "bt709", transfer: String = "bt709", matrix: String = "bt709", range: String = "video") {
        self.codec = codec
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrateKbps = bitrateKbps
        self.primaries = primaries
        self.transfer = transfer
        self.matrix = matrix
        self.range = range
    }
}

public struct Welcome: Codable, Hashable, Sendable {
    public struct Mac: Codable, Hashable, Sendable {
        public var name: String
        public var os: String
        public var app: String
        public init(name: String, os: String, app: String) { self.name = name; self.os = os; self.app = app }
    }

    public var version: Int
    public var session: String
    public var mac: Mac
    public var display: DisplayDescription
    public var stream: StreamDescription
    public var features: [String]?

    enum CodingKeys: String, CodingKey {
        case version = "protocol"
        case session, mac, display, stream, features
    }

    public init(version: Int, session: String, mac: Mac, display: DisplayDescription, stream: StreamDescription, features: [String]?) {
        self.version = version
        self.session = session
        self.mac = mac
        self.display = display
        self.stream = stream
        self.features = features
    }
}

public struct Configure: Codable, Hashable, Sendable {
    public struct Request: Codable, Hashable, Sendable {
        public var orientation: String?
        public var refreshRate: Double?
        public var resolution: PixelDimensions?
        /// The receiver can't show video right now (app in the background, screen off): stop
        /// sending frames until `false`. Only sent when WELCOME lists the "pause" feature.
        public var paused: Bool?
        public init(orientation: String? = nil, refreshRate: Double? = nil, resolution: PixelDimensions? = nil, paused: Bool? = nil) {
            self.orientation = orientation
            self.refreshRate = refreshRate
            self.resolution = resolution
            self.paused = paused
        }
    }

    public var request: Request?
    public var display: DisplayDescription?
    public var stream: StreamDescription?

    public init(request: Request? = nil, display: DisplayDescription? = nil, stream: StreamDescription? = nil) {
        self.request = request
        self.display = display
        self.stream = stream
    }
}

public struct StreamFormat: Codable, Hashable, Sendable {
    public var codec: String
    public var width: Int
    public var height: Int
    /// VPS/SPS/PPS (HEVC) or SPS/PPS (H.264) without start codes; base64 in JSON.
    public var parameterSets: [Data]

    public init(codec: String, width: Int, height: Int, parameterSets: [Data]) {
        self.codec = codec
        self.width = width
        self.height = height
        self.parameterSets = parameterSets
    }
}

public struct ReceiverReport: Codable, Hashable, Sendable {
    public struct Percentiles: Codable, Hashable, Sendable {
        public var p50: Double
        public var p95: Double
        public init(p50: Double, p95: Double) { self.p50 = p50; self.p95 = p95 }
    }

    public var lastFrameId: UInt32?
    public var framesReceived: Int?
    public var framesDecoded: Int?
    public var framesRendered: Int?
    public var framesDropped: Int?
    public var bytesReceived: Int?
    public var decodeMs: Percentiles?
    public var endToEndMs: Percentiles?
    public var decoderQueue: Int?
    public var clockOffsetUs: Int64?
    public var rttUs: Int64?

    public init(
        lastFrameId: UInt32? = nil, framesReceived: Int? = nil, framesDecoded: Int? = nil, framesRendered: Int? = nil,
        framesDropped: Int? = nil, bytesReceived: Int? = nil, decodeMs: Percentiles? = nil, endToEndMs: Percentiles? = nil,
        decoderQueue: Int? = nil, clockOffsetUs: Int64? = nil, rttUs: Int64? = nil
    ) {
        self.lastFrameId = lastFrameId
        self.framesReceived = framesReceived
        self.framesDecoded = framesDecoded
        self.framesRendered = framesRendered
        self.framesDropped = framesDropped
        self.bytesReceived = bytesReceived
        self.decodeMs = decodeMs
        self.endToEndMs = endToEndMs
        self.decoderQueue = decoderQueue
        self.clockOffsetUs = clockOffsetUs
        self.rttUs = rttUs
    }
}

public struct KeyframeRequest: Codable, Hashable, Sendable {
    public var reason: String
    public var lastDecodedFrameId: UInt32?
    public init(reason: String, lastDecodedFrameId: UInt32? = nil) {
        self.reason = reason
        self.lastDecodedFrameId = lastDecodedFrameId
    }
}

public struct ErrorMessage: Codable, Hashable, Sendable {
    public var code: String
    public var message: String
    public init(code: String, message: String) { self.code = code; self.message = message }
}

public struct Goodbye: Codable, Hashable, Sendable {
    public var reason: String
    public init(reason: String) { self.reason = reason }
}

/// Wi‑Fi pairing by numeric comparison (§6). Both sides derive the same 6-digit code from the
/// TLS certificates; nothing secret travels in these messages.
public struct Pairing: Codable, Hashable, Sendable {
    /// An open set: a state this side doesn't know decodes, and the receiver ignores it.
    public struct State: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// Mac → tablet: this tablet isn't paired; `name` names the Mac. The tablet answers `commit`.
        public static let required = State(rawValue: "required")
        /// Tablet → Mac: `commitment` to the tablet's nonce, before it has seen the Mac's.
        public static let commit = State(rawValue: "commit")
        /// Mac → tablet: the Mac's `nonce`.
        public static let nonce = State(rawValue: "nonce")
        /// Tablet → Mac: the tablet's `nonce`, which must match its commitment. Both screens now
        /// show the code.
        public static let reveal = State(rawValue: "reveal")
        /// Tablet → Mac: its user confirmed that the codes match.
        public static let confirmed = State(rawValue: "confirmed")
        /// Mac → tablet: both users confirmed; the Mac pinned the tablet (the tablet pins the Mac now).
        public static let paired = State(rawValue: "paired")
        /// Either side: the user declined, the codes differ, or the exchange broke the rules.
        public static let rejected = State(rawValue: "rejected")

        public var description: String { rawValue }
    }

    public var state: State
    /// The sender's display name (e.g. "Kelvin's MacBook Air").
    public var name: String?
    /// `commit`: SHA-256(tabletFingerprint ‖ macFingerprint ‖ tabletNonce), 64 hex digits.
    public var commitment: String?
    /// `nonce` and `reveal`: 32 random bytes, 64 hex digits.
    public var nonce: String?

    public init(state: State, name: String? = nil, commitment: String? = nil, nonce: String? = nil) {
        self.state = state
        self.name = name
        self.commitment = commitment
        self.nonce = nonce
    }
}

// MARK: - Binary hot-path messages (§3.2–3.4)

public struct VideoFrame: Hashable, Sendable {
    public static let headerLengthV1: UInt16 = 18

    public var frameId: UInt32
    /// WindowServer composition time, Mac host clock, µs.
    public var captureTimeUs: UInt64
    public var encodeDurationUs: UInt32
    public var isKeyframe: Bool
    /// One access unit as an Annex‑B byte stream.
    public var data: Data

    public init(frameId: UInt32, captureTimeUs: UInt64, encodeDurationUs: UInt32, isKeyframe: Bool, data: Data) {
        self.frameId = frameId
        self.captureTimeUs = captureTimeUs
        self.encodeDurationUs = encodeDurationUs
        self.isKeyframe = isKeyframe
        self.data = data
    }
}

public struct InputKind: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let touch = InputKind(rawValue: 1)
    public static let stylus = InputKind(rawValue: 2)
    public static let mouse = InputKind(rawValue: 3)
}

public struct InputAction: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let down = InputAction(rawValue: 0)
    public static let move = InputAction(rawValue: 1)
    public static let up = InputAction(rawValue: 2)
    public static let cancel = InputAction(rawValue: 3)
    public static let hoverEnter = InputAction(rawValue: 4)
    public static let hoverMove = InputAction(rawValue: 5)
    public static let hoverExit = InputAction(rawValue: 6)
    public static let pointerDown = InputAction(rawValue: 7)
    public static let pointerUp = InputAction(rawValue: 8)
}

public struct ToolType: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let unknown = ToolType(rawValue: 0)
    public static let finger = ToolType(rawValue: 1)
    public static let stylus = ToolType(rawValue: 2)
    public static let eraser = ToolType(rawValue: 3)
    public static let mouse = ToolType(rawValue: 4)
}

public struct PointerButtons: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public static let primary = PointerButtons(rawValue: 1 << 0)
    public static let secondary = PointerButtons(rawValue: 1 << 1)
    public static let stylusPrimary = PointerButtons(rawValue: 1 << 2)
    public static let stylusSecondary = PointerButtons(rawValue: 1 << 3)
}

public struct PointerRecord: Hashable, Sendable {
    public static let recordLengthV1: UInt16 = 18

    public var pointerId: UInt8
    public var toolType: ToolType
    public var buttons: PointerButtons
    /// 0…65535 across the stream's width/height.
    public var x: UInt16
    public var y: UInt16
    public var pressure: UInt16
    public var tiltX: Int16
    public var tiltY: Int16
    public var distance: UInt16

    public init(pointerId: UInt8, toolType: ToolType, buttons: PointerButtons = [], x: UInt16, y: UInt16,
                pressure: UInt16 = 0, tiltX: Int16 = 0, tiltY: Int16 = 0, distance: UInt16 = 0) {
        self.pointerId = pointerId
        self.toolType = toolType
        self.buttons = buttons
        self.x = x
        self.y = y
        self.pressure = pressure
        self.tiltX = tiltX
        self.tiltY = tiltY
        self.distance = distance
    }
}

public struct InputMessage: Hashable, Sendable {
    public static let headerLengthV1: UInt16 = 16

    public var sequence: UInt32
    /// Android clock (§5), µs.
    public var eventTimeUs: UInt64
    public var kind: InputKind
    public var action: InputAction
    public var pointers: [PointerRecord]

    public init(sequence: UInt32, eventTimeUs: UInt64, kind: InputKind, action: InputAction, pointers: [PointerRecord]) {
        self.sequence = sequence
        self.eventTimeUs = eventTimeUs
        self.kind = kind
        self.action = action
        self.pointers = pointers
    }
}

public struct Ping: Hashable, Sendable {
    public var id: UInt32
    public var t1: UInt64
    public init(id: UInt32, t1: UInt64) { self.id = id; self.t1 = t1 }
}

public struct Pong: Hashable, Sendable {
    public var id: UInt32
    public var t1: UInt64
    public var t2: UInt64
    public var t3: UInt64
    public init(id: UInt32, t1: UInt64, t2: UInt64, t3: UInt64) { self.id = id; self.t1 = t1; self.t2 = t2; self.t3 = t3 }
}

// MARK: - Cursor side channel (§3.3b)

/// Where the pointer is on the display (CURSOR, 0x12): sent instead of drawing it into the video.
public struct CursorPosition: Hashable, Sendable {
    public static let headerLengthV1: UInt16 = 24

    public var sequence: UInt32
    /// Mac clock, µs.
    public var timeUs: UInt64
    /// The hotspot, 0…65535 across the display.
    public var x: UInt16
    public var y: UInt16
    public var visible: Bool
    public var shapeId: UInt32

    public init(sequence: UInt32, timeUs: UInt64, x: UInt16, y: UInt16, visible: Bool, shapeId: UInt32) {
        self.sequence = sequence
        self.timeUs = timeUs
        self.x = x
        self.y = y
        self.visible = visible
        self.shapeId = shapeId
    }
}

/// A pointer image (CURSOR_SHAPE, 0x13), sent once per shape per session.
public struct CursorShape: Hashable, Sendable {
    public static let headerLengthV1: UInt16 = 14

    public var shapeId: UInt32
    /// Image size and hotspot, in stream pixels.
    public var width: UInt16
    public var height: UInt16
    public var hotspotX: UInt16
    public var hotspotY: UInt16
    public var png: Data

    public init(shapeId: UInt32, width: UInt16, height: UInt16, hotspotX: UInt16, hotspotY: UInt16, png: Data) {
        self.shapeId = shapeId
        self.width = width
        self.height = height
        self.hotspotX = hotspotX
        self.hotspotY = hotspotY
        self.png = png
    }
}

// MARK: - Direct link (§6b)

/// The key for the no-router mode (DIRECT_LINK, 0x08), sent over an authenticated session.
public struct DirectLink: Codable, Hashable, Sendable {
    /// 8 bytes, 16 hex digits: names the key in the Bluetooth handover.
    public var keyId: String
    /// 32 bytes, 64 hex digits.
    public var key: String

    public init(keyId: String, key: String) {
        self.keyId = keyId
        self.key = key
    }
}

// MARK: - Keyboard (§3.3c)

/// A key of a hardware keyboard attached to the tablet (KEY, 0x14).
public struct KeyMessage: Hashable, Sendable {
    public static let headerLengthV1: UInt16 = 20

    public enum Action: UInt8, Sendable { case down = 0, up = 1 }

    /// HID modifier bits (§3.3c), plus caps lock.
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        public static let leftControl = Modifiers(rawValue: 1 << 0)
        public static let leftShift = Modifiers(rawValue: 1 << 1)
        public static let leftAlt = Modifiers(rawValue: 1 << 2)
        public static let leftMeta = Modifiers(rawValue: 1 << 3)
        public static let rightControl = Modifiers(rawValue: 1 << 4)
        public static let rightShift = Modifiers(rawValue: 1 << 5)
        public static let rightAlt = Modifiers(rawValue: 1 << 6)
        public static let rightMeta = Modifiers(rawValue: 1 << 7)
        public static let capsLock = Modifiers(rawValue: 1 << 8)
    }

    public var sequence: UInt32
    public var eventTimeUs: UInt64
    public var action: Action
    /// USB HID usage, Keyboard/Keypad page.
    public var usage: UInt16
    public var modifiers: Modifiers

    public init(sequence: UInt32, eventTimeUs: UInt64, action: Action, usage: UInt16, modifiers: Modifiers) {
        self.sequence = sequence
        self.eventTimeUs = eventTimeUs
        self.action = action
        self.usage = usage
        self.modifiers = modifiers
    }
}

