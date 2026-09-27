import CoreVideo
import Foundation
import GingaCore
import GingaProtocol
import GingaSecurity
import GingaSession
import Testing
import Transport
import VideoPipeline
@testable import GingaStreaming

/// A receiver on the Mac side of the loopback, standing in for the Android app.
final class TestReceiver: @unchecked Sendable {
    let connection: MessageConnection
    private let lock = NSLock()
    private var messages: [Message] = []
    private var closeReasons: [MessageConnection.CloseReason] = []

    private var pinger: DispatchSourceTimer?

    /// - Parameter pings: PING every second, as the tablet does (the Mac drops silent receivers).
    init(port: UInt16, pings: Bool = true) {
        connection = MessageConnection.connect(host: "127.0.0.1", port: port)
        connection.setHandlers(
            onMessage: { [weak self] message in self?.lock.withLock { self?.messages.append(message) } },
            onClose: { [weak self] reason in self?.lock.withLock { self?.closeReasons.append(reason) } }
        )
        connection.start()
        guard pings else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 0.5, repeating: 1)
        timer.setEventHandler { [connection] in connection.send(.ping(Ping(id: 1, t1: 1))) }
        timer.resume()
        pinger = timer
    }

    deinit { pinger?.cancel() }

    func stopPinging() {
        pinger?.cancel()
    }

    var received: [Message] { lock.withLock { messages } }
    var closed: Bool { lock.withLock { !closeReasons.isEmpty } }

    var videoFrames: [VideoFrame] {
        received.compactMap { if case .videoFrame(let frame) = $0 { frame } else { nil } }
    }

    func first<T>(_ extract: (Message) -> T?) -> T? {
        received.lazy.compactMap(extract).first
    }

    func sendHello(decoders: [String] = ["video/hevc", "video/avc"], maxFps: Double = 120, versions: Hello.VersionRange = .init(min: 1, max: 1), features: [String] = ["clock-sync"], loopbackToken: String? = nil, pairingRequested: Bool? = nil) {
        connection.send(.hello(Hello(
            versions: versions,
            app: .init(name: "Test receiver", version: "1"),
            device: .init(manufacturer: "samsung", model: "SM-X730", android: "16", id: "test"),
            display: .init(widthPx: 2560, heightPx: 1600, densityDpi: 274, refreshRates: [60, 120], rotation: 0),
            decoders: decoders.map { .init(mime: $0, profiles: [], maxWidth: 4096, maxHeight: 2176, maxFps: maxFps, lowLatency: true) },
            input: nil, transport: "test", features: features, loopbackToken: loopbackToken, pairingRequested: pairingRequested
        )))
    }
}

@MainActor
func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@MainActor
@Suite("Streaming (loopback, synthetic source)", .serialized, .enabled(if: VideoToolboxEncoder.isHardwareEncoderAvailable(.hevc)))
struct StreamingTests {
    let host = SyntheticStreamHost(size: PixelSize(width: 640, height: 400), frameRate: 60)

    private func startServer(codec: VideoCodec = .hevc, helloTimeout: Double = 5) async throws -> (StreamServer, UInt16) {
        let settings = StreamingSettings(codec: codec, bitrateKbps: 4000, port: 0, adbAutoReverse: false, helloTimeoutSeconds: helloTimeout)
        let server = StreamServer(host: host, settings: settings, adb: nil)
        try server.start(port: 0)
        #expect(await eventually { server.status.listeningPort != nil })
        return (server, try #require(server.status.listeningPort))
    }

    @Test func handshakeThenDecodableVideo() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()

        #expect(await eventually { receiver.videoFrames.count >= 10 })
        let welcome = try #require(receiver.first { if case .welcome(let welcome) = $0 { welcome } else { nil } })
        #expect(welcome.version == 1)
        #expect(welcome.stream.codec == "hevc")
        #expect(welcome.stream.width == 640 && welcome.stream.height == 400)

        // Order on the wire: WELCOME, STREAM_FORMAT, then the first (key)frame.
        let kinds = receiver.received.prefix(3).map { message -> String in
            switch message {
            case .welcome: "welcome"
            case .streamFormat: "format"
            case .videoFrame(let frame): frame.isKeyframe ? "keyframe" : "delta"
            default: "other"
            }
        }
        #expect(kinds == ["welcome", "format", "keyframe"])

        let format = try #require(receiver.first { if case .streamFormat(let format) = $0 { format } else { nil } })
        #expect(format.parameterSets.count == 3)
        let decoder = try VideoToolboxDecoder(codec: .hevc, parameterSets: format.parameterSets)
        let decoded = Counter()
        for frame in receiver.videoFrames.prefix(10) {
            decoder.decode(frame.data) { result in
                if case .success(let picture) = result, CVPixelBufferGetWidth(picture.pixelBuffer) == 640 { decoded.increment() }
            }
        }
        decoder.waitForPendingFrames()
        #expect(decoded.value == 10)
        #expect(receiver.videoFrames.map(\.frameId).prefix(10) == Array(1...10)[...])
    }

    @Test func pingIsAnsweredWithMacTimestamps() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        receiver.connection.send(.ping(Ping(id: 5, t1: 123)))
        #expect(await eventually { receiver.first { if case .pong = $0 { true } else { nil } } != nil })
        let pong = try #require(receiver.first { if case .pong(let pong) = $0 { pong } else { nil } })
        #expect(pong.id == 5 && pong.t1 == 123)
        #expect(pong.t2 <= pong.t3)
        #expect(pong.t2 > 0)
    }

    @Test func keyframeRequestIsHonoured() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        #expect(await eventually { receiver.videoFrames.count >= 5 })
        let before = receiver.videoFrames.count
        receiver.connection.send(.keyframeRequest(KeyframeRequest(reason: "decoder-error", lastDecodedFrameId: 3)))
        #expect(await eventually { receiver.videoFrames.dropFirst(before).contains(where: \.isKeyframe) })
    }

    /// A static screen produces no new frames; a keyframe request must still be answered.
    @Test func keyframeRequestIsAnsweredOnAStaticScreen() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        #expect(await eventually { receiver.videoFrames.count >= 5 })
        host.setStill(true)  // the generator stops: nothing changes on "screen"
        try await Task.sleep(for: .milliseconds(100))
        let before = receiver.videoFrames.count
        receiver.connection.send(.keyframeRequest(KeyframeRequest(reason: "decoder-error", lastDecodedFrameId: 3)))
        #expect(await eventually { receiver.videoFrames.dropFirst(before).contains(where: \.isKeyframe) })
    }

    /// Frames skipped to hold the stream rate must not leave the tablet on a stale picture: when
    /// the source stops (the screen goes still), its last frame is sent after all.
    @Test func theLastFrameBeforeTheScreenGoesStillIsAlwaysSent() async throws {
        let fast = SyntheticStreamHost(size: PixelSize(width: 640, height: 400), frameRate: 60, generationRate: 120)
        let server = StreamServer(host: fast, settings: StreamingSettings(bitrateKbps: 4000, port: 0, adbAutoReverse: false), adb: nil)
        try server.start(port: 0)
        defer { server.stop() }
        #expect(await eventually { server.status.listeningPort != nil })
        let receiver = TestReceiver(port: try #require(server.status.listeningPort))
        receiver.sendHello()
        #expect(await eventually { receiver.videoFrames.count >= 20 })
        fast.setStill(true)  // the source stops at an arbitrary frame
        try await Task.sleep(for: .milliseconds(50))  // a tick already running finishes
        let last = try #require(fast.latestFrame)
        let lastUs = last.captureTime.nanoseconds / 1000
        #expect(await eventually { receiver.videoFrames.last?.captureTimeUs == lastUs })
    }

    /// Streaming at the display's own rate there is nothing to cap: the source's timing jitter
    /// (a timer here, vsync-aligned capture on the Mac) must never cost a frame at 120 Hz.
    @Test func atTheDisplaysRateNoFrameIsSkippedForTheRate() async throws {
        let fast = SyntheticStreamHost(size: PixelSize(width: 640, height: 400), frameRate: 120)
        let server = StreamServer(host: fast, settings: StreamingSettings(bitrateKbps: 4000, port: 0, adbAutoReverse: false), adb: nil)
        try server.start(port: 0)
        defer { server.stop() }
        #expect(await eventually { server.status.listeningPort != nil })
        let receiver = TestReceiver(port: try #require(server.status.listeningPort))
        receiver.sendHello()
        #expect(await eventually { receiver.videoFrames.count >= 120 })
        server.refresh()
        #expect(server.status.connection?.framesSkippedForRateLimit == 0)
    }

    /// 120 Hz on the power adapter, 60 Hz on battery: the stream follows the display, and the
    /// tablet hears the new rate (so its panel can follow too).
    @Test func aRefreshRateChangeIsAnnouncedAndTheStreamFollows() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        #expect(await eventually { receiver.videoFrames.count >= 5 })
        await host.changeRate(to: 30)
        let announced = await eventually {
            receiver.received.contains { if case .configure(let configure) = $0 { configure.stream?.fps == 30 } else { false } }
        }
        #expect(announced)
        let before = receiver.videoFrames.count
        #expect(await eventually { receiver.videoFrames.count >= before + 5 })
        #expect(receiver.videoFrames.dropFirst(before).contains { $0.isKeyframe })  // new encoder
    }

    /// Rate and power flips while frames are inside the encoder (two in flight) must not lose the
    /// pacer's slots (the stream would freeze for good) or send frames out of order.
    @Test func manyEncoderSwitchesUnderLoadKeepTheStreamAlive() async throws {
        let fast = SyntheticStreamHost(size: PixelSize(width: 640, height: 400), frameRate: 120)
        let server = StreamServer(host: fast, settings: StreamingSettings(bitrateKbps: 4000, port: 0, adbAutoReverse: false), adb: nil)
        try server.start(port: 0)
        defer { server.stop() }
        #expect(await eventually { server.status.listeningPort != nil })
        let receiver = TestReceiver(port: try #require(server.status.listeningPort))
        receiver.sendHello()
        #expect(await eventually { receiver.videoFrames.count >= 10 })
        for flip in 0..<20 {
            await fast.changeRate(to: flip.isMultiple(of: 2) ? 60 : 120)
            try await Task.sleep(for: .milliseconds(15))
        }
        let afterFlips = receiver.videoFrames.count
        #expect(await eventually { receiver.videoFrames.count >= afterFlips + 30 })  // still flowing
        let ids = receiver.videoFrames.map(\.frameId)
        #expect(ids == Array(try #require(ids.first)...(try #require(ids.last))))  // none lost after encoding
        fast.setStill(true)  // quiesce: every encoder slot must come back
        #expect(await eventually {
            server.refresh()
            return server.status.connection?.encoderFramesInFlight == 0
        })
    }

    /// The tablet's app went to the background: no video until it resumes, then a keyframe.
    @Test func pauseStopsVideoAndResumeStartsWithAKeyframe() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        #expect(await eventually { receiver.videoFrames.count >= 5 })
        let welcome = try #require(receiver.first { if case .welcome(let welcome) = $0 { welcome } else { nil } })
        #expect(welcome.features?.contains("pause") == true)

        receiver.connection.send(.configure(Configure(request: .init(paused: true))))
        #expect(await eventually { host.leasePauseStates == [true] && !host.isGenerating })
        try await Task.sleep(for: .milliseconds(100))  // frames already in flight arrive
        let paused = receiver.videoFrames.count
        try await Task.sleep(for: .milliseconds(200))
        #expect(receiver.videoFrames.count == paused)

        receiver.connection.send(.configure(Configure(request: .init(paused: false))))
        #expect(await eventually { host.leasePauseStates == [false] && host.isGenerating })
        #expect(await eventually { receiver.videoFrames.dropFirst(paused).first?.isKeyframe == true })
    }

    @Test func orientationRequestsAndInputReachTheHost() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        #expect(await eventually { !receiver.videoFrames.isEmpty })
        receiver.connection.send(.configure(Configure(request: .init(orientation: "portrait"))))
        let input = InputMessage(sequence: 1, eventTimeUs: 10, kind: .touch, action: .down, pointers: [PointerRecord(pointerId: 0, toolType: .finger, x: 100, y: 200)])
        receiver.connection.send(.input(input))
        #expect(await eventually { host.orientationRequests == ["portrait"] && host.receivedInput == [input] })
        #expect(host.inputEnds == 0)
        receiver.connection.close(reason: "gone mid-gesture")
        #expect(await eventually { host.inputEnds == 1 })  // the host releases what the receiver held
    }

    @Test func fallsBackToH264WhenHEVCIsUnavailable() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(decoders: ["video/avc"])
        #expect(await eventually { !receiver.videoFrames.isEmpty })
        let format = try #require(receiver.first { if case .streamFormat(let format) = $0 { format } else { nil } })
        #expect(format.codec == "h264")
        #expect(format.parameterSets.count == 2)
    }

    @Test func incompatibleVersionIsRejectedWithErrorAndGoodbye() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(versions: .init(min: 2, max: 3))
        #expect(await eventually { receiver.closed })
        let error = try #require(receiver.first { if case .error(let error) = $0 { error } else { nil } })
        #expect(error.code == "incompatible-version")
        #expect(receiver.first { if case .goodbye(let goodbye) = $0 { goodbye } else { nil } }?.reason == "error")
    }

    @Test func silentClientsAreDisconnected() async throws {
        let (server, port) = try await startServer(helloTimeout: 0.3)
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        #expect(await eventually { receiver.closed })
    }

    @Test func aNewReceiverReplacesTheOldOne() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let first = TestReceiver(port: port)
        first.sendHello()
        #expect(await eventually { !first.videoFrames.isEmpty })
        let second = TestReceiver(port: port)
        second.sendHello()
        #expect(await eventually { first.closed && !second.videoFrames.isEmpty })
        #expect(first.first { if case .goodbye(let goodbye) = $0 { goodbye } else { nil } }?.reason == "replaced")
    }

    /// Anyone who can reach the port can open a connection: only one that completed the
    /// handshake and streams may replace the receiver.
    @Test func aConnectionThatNeverSaysHelloDoesNotDisplaceTheReceiver() async throws {
        let (server, port) = try await startServer(helloTimeout: 0.3)
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        #expect(await eventually { !receiver.videoFrames.isEmpty })
        let silent = TestReceiver(port: port)
        #expect(await eventually { silent.closed })  // HELLO timeout
        let before = receiver.videoFrames.count
        #expect(await eventually { receiver.videoFrames.count > before + 5 })
        #expect(!receiver.closed)
        server.refresh()
        #expect(server.status.connection?.phase == .streaming)
    }

    @Test func requestsBeforeTheHandshakeAreIgnored() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let client = TestReceiver(port: port)
        client.connection.send(.configure(Configure(request: .init(orientation: "portrait", paused: true))))
        client.connection.send(.input(InputMessage(sequence: 1, eventTimeUs: 10, kind: .touch, action: .down, pointers: [PointerRecord(pointerId: 0, toolType: .finger, x: 1, y: 1)])))
        try await Task.sleep(for: .milliseconds(200))
        #expect(host.orientationRequests.isEmpty)
        #expect(host.receivedInput.isEmpty)
        // The session itself is unaffected, and not paused.
        client.sendHello()
        #expect(await eventually { !client.videoFrames.isEmpty })
        #expect(host.leasePauseStates == [false])
    }

    /// The tablet left while the Mac was still setting up (creating the display): its hold on
    /// the host is released, so no display or capture is stranded.
    @Test func aReceiverLeavingDuringSetupLeavesNothingBehind() async throws {
        host.prepareDelay = .milliseconds(300)
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        #expect(await eventually { host.activeLeaseCount == 1 })
        receiver.connection.close(reason: "gone")
        #expect(await eventually { host.activeLeaseCount == 0 && !host.isGenerating })
        try await Task.sleep(for: .milliseconds(100))
        #expect(host.activeLeaseCount == 0)
        #expect(!host.isGenerating)
    }

    /// The Mac is kept from napping and idle-sleeping only while a receiver actually shows the
    /// stream: not for a connection that hasn't authenticated, nor while the tablet app is paused.
    @Test func theActivityIsHeldOnlyWhileAReceiverWatches() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!server.holdsActivity)
        receiver.sendHello()
        #expect(await eventually { server.holdsActivity })
        receiver.connection.send(.configure(Configure(request: .init(paused: true))))
        #expect(await eventually { !server.holdsActivity })
        receiver.connection.send(.configure(Configure(request: .init(paused: false))))
        #expect(await eventually { server.holdsActivity })
        receiver.connection.close(reason: "done")
        #expect(await eventually { !server.holdsActivity })
    }

    @Test func closeSessionsEndsTheSelectedReceivers() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        #expect(await eventually { !receiver.videoFrames.isEmpty })
        server.closeSessions(reason: "revoked") { _ in false }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!receiver.closed)
        server.closeSessions(reason: "revoked") { _ in true }
        #expect(await eventually { receiver.closed })
        #expect(receiver.first { if case .goodbye(let goodbye) = $0 { goodbye } else { nil } }?.reason == "revoked")
        #expect(await eventually { host.activeLeaseCount == 0 })
    }

    /// "Accept the tablet over USB" off ends adb sessions only: direct USB and Wi‑Fi receivers
    /// have their own switches.
    @Test func stoppingTheListenerLeavesOtherTransportsAlone() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let viaAdb = TestReceiver(port: port)
        viaAdb.sendHello()
        #expect(await eventually { !viaAdb.videoFrames.isEmpty })

        // Another transport, standing in for USB accessory or Wi‑Fi: its connections are handed
        // to the server with accept().
        let other = try TCPServer(port: 0, loopbackOnly: true)
        let otherPort = Recorder<UInt16>()
        other.start { event in
            switch event {
            case .listening(let port): otherPort.append(port)
            case .connection(let connection): Task { @MainActor in server.accept(connection) }
            case .failed: break
            }
        }
        defer { other.stop() }
        #expect(await eventually { !otherPort.values.isEmpty })
        let viaOther = TestReceiver(port: try #require(otherPort.values.first))
        viaOther.sendHello()
        #expect(await eventually { !viaOther.videoFrames.isEmpty && viaAdb.closed })  // it replaced the adb one

        let adbAgain = TestReceiver(port: port)  // pending on the listener while `viaOther` streams
        try await Task.sleep(for: .milliseconds(50))
        server.stop()
        #expect(await eventually { adbAgain.closed })
        let before = viaOther.videoFrames.count
        #expect(await eventually { viaOther.videoFrames.count > before + 3 })
        #expect(!viaOther.closed)
    }

    /// Over adb the connection is a loopback one any local process could open: only one that
    /// presents the token the Mac handed the tablet app over adb gets the stream.
    @Test func loopbackConnectionsNeedTheToken() async throws {
        let settings = StreamingSettings(bitrateKbps: 4000, port: 0, adbAutoReverse: false)
        let server = StreamServer(host: host, settings: settings, adb: nil)
        let token = LoopbackToken.generate()
        server.requireLoopbackToken(token)
        try server.start(port: 0)
        defer { server.stop() }
        #expect(await eventually { server.status.listeningPort != nil })
        let port = try #require(server.status.listeningPort)

        for wrong in [nil, LoopbackToken.generate()] {
            let intruder = TestReceiver(port: port)
            intruder.sendHello(loopbackToken: wrong)
            #expect(await eventually { intruder.closed })
            #expect(intruder.first { if case .error(let error) = $0 { error } else { nil } }?.code == "unauthorized")
            #expect(intruder.videoFrames.isEmpty)
        }
        #expect(host.activeLeaseCount == 0)  // nothing was prepared for them

        let tablet = TestReceiver(port: port)
        tablet.sendHello(loopbackToken: token)
        #expect(await eventually { !tablet.videoFrames.isEmpty })
    }

    /// A tablet that draws the pointer gets it as CURSOR messages (its shape once) instead of in
    /// the video, so moving it over a still screen costs a small message, not a frame.
    @Test func thePointerComesAsItsOwnMessagesWhenTheTabletDrawsIt() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(features: ["clock-sync", "cursor"])
        #expect(await eventually { !receiver.videoFrames.isEmpty })
        let welcome = try #require(receiver.first { if case .welcome(let welcome) = $0 { welcome } else { nil } })
        #expect(welcome.features?.contains("cursor") == true)
        #expect(host.leaseCursorStates == [true])

        let arrow = CursorTracker.Shape(id: 7, width: 34, height: 44, hotspotX: 8, hotspotY: 6, png: Data([1, 2, 3]))
        host.moveCursor(CursorUpdate(x: 100, y: 200, visible: true, shape: arrow))
        host.moveCursor(CursorUpdate(x: 150, y: 250, visible: true, shape: arrow))
        host.moveCursor(CursorUpdate(x: 0, y: 0, visible: false, shape: arrow))
        func cursors() -> [CursorPosition] { receiver.received.compactMap { if case .cursor(let cursor) = $0 { cursor } else { nil } } }
        #expect(await eventually { cursors().count == 3 })
        let shapes = receiver.received.compactMap { if case .cursorShape(let shape) = $0 { shape } else { nil } }
        #expect(shapes.map(\.shapeId) == [7])  // once per session
        #expect(shapes.first?.hotspotX == 8 && shapes.first?.png == Data([1, 2, 3]))
        #expect(cursors().map(\.x) == [100, 150, 0])
        #expect(cursors().map(\.visible) == [true, true, false])
        #expect(cursors().map(\.sequence) == [1, 2, 3])
        // The shape arrived before the first position that uses it.
        let order = receiver.received.compactMap { message -> String? in
            switch message {
            case .cursorShape: "shape"
            case .cursor: "cursor"
            default: nil
            }
        }
        #expect(order.first == "shape")
    }

    /// A new HELLO on the same link (the tablet app restarted; it forgot its shapes) gets the
    /// pointer's shape again, and where the pointer is right away, without waiting for it to move.
    @Test func aRestartedSessionGetsThePointerShapeAgain() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(features: ["clock-sync", "cursor"])
        #expect(await eventually { !receiver.videoFrames.isEmpty })
        let arrow = CursorTracker.Shape(id: 7, width: 34, height: 44, hotspotX: 8, hotspotY: 6, png: Data([1, 2, 3]))
        host.moveCursor(CursorUpdate(x: 100, y: 200, visible: true, shape: arrow))
        func shapes() -> [CursorShape] { receiver.received.compactMap { if case .cursorShape(let shape) = $0 { shape } else { nil } } }
        func cursors() -> [CursorPosition] { receiver.received.compactMap { if case .cursor(let cursor) = $0 { cursor } else { nil } } }
        #expect(await eventually { cursors().count == 1 })

        receiver.sendHello(features: ["clock-sync", "cursor"])
        func welcomes() -> Int { receiver.received.filter { if case .welcome = $0 { true } else { false } }.count }
        #expect(await eventually { welcomes() == 2 })
        // Without the pointer moving: the shape again, then the position, numbered from 1.
        #expect(await eventually { shapes().count == 2 && cursors().count == 2 })
        #expect(shapes().map(\.shapeId) == [7, 7])
        #expect(cursors().last?.sequence == 1 && cursors().last?.x == 100)
    }

    @Test func withoutTheFeatureThePointerStaysInTheVideo() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        #expect(await eventually { !receiver.videoFrames.isEmpty })
        #expect(receiver.first { if case .welcome(let welcome) = $0 { welcome } else { nil } }?.features?.contains("cursor") == false)
        #expect(host.leaseCursorStates == [false])
        host.moveCursor(CursorUpdate(x: 1, y: 1, visible: true, shape: nil))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!receiver.received.contains { if case .cursor = $0 { true } else { false } })
    }

    /// Quitting tells every receiver, whatever its transport, so it can reconnect later.
    @Test func shutdownSaysGoodbyeToEveryReceiver() async throws {
        let (server, port) = try await startServer()
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        #expect(await eventually { !receiver.videoFrames.isEmpty })
        #expect(server.shutdown(timeout: .seconds(2)))
        #expect(await eventually { receiver.closed })
        #expect(receiver.first { if case .goodbye(let goodbye) = $0 { goodbye } else { nil } }?.reason == "shutdown")
    }

    /// The tablet's app restarted on a link that doesn't report it (USB accessory): its new HELLO
    /// starts a fresh session on the same connection instead of being ignored.
    @Test func aNewHelloOnALiveLinkStartsOver() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        #expect(await eventually { receiver.videoFrames.count >= 5 })
        receiver.sendHello()
        func welcomes() -> Int { receiver.received.filter { if case .welcome = $0 { true } else { false } }.count }
        #expect(await eventually { welcomes() == 2 })
        #expect(await eventually { receiver.videoFrames.last?.frameId ?? 0 < 20 && receiver.videoFrames.contains { $0.frameId == 1 && $0.isKeyframe } })
        let after = receiver.videoFrames.count
        #expect(await eventually { receiver.videoFrames.count > after + 5 })
        #expect(!receiver.closed)
        #expect(host.activeLeaseCount == 1)
    }

    /// A receiver that goes silent while streaming is dropped (the watchdog), so a USB accessory
    /// link can be offered afresh.
    @Test func aSilentReceiverIsDropped() async throws {
        let saved = StreamConnection.silenceTimeout
        StreamConnection.silenceTimeout = .milliseconds(1500)
        defer { StreamConnection.silenceTimeout = saved }
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port, pings: false)
        receiver.sendHello()
        #expect(await eventually { !receiver.videoFrames.isEmpty })
        #expect(await eventually(timeout: .seconds(5)) { receiver.closed })
        #expect(await eventually { host.activeLeaseCount == 0 })
    }

    @Test func aReceiverThatPingsIsKept() async throws {
        let saved = StreamConnection.silenceTimeout
        StreamConnection.silenceTimeout = .milliseconds(1500)
        defer { StreamConnection.silenceTimeout = saved }
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello()
        try await Task.sleep(for: .seconds(3))
        #expect(!receiver.closed)
    }

    /// A keyboard cover's keys reach the Mac once the session streams, never before.
    @Test func keysReachTheHostOnlyWhileStreaming() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        let key = KeyMessage(sequence: 1, eventTimeUs: 1, action: .down, usage: 0x04, modifiers: [.leftShift])
        receiver.connection.send(.key(key))
        try await Task.sleep(for: .milliseconds(100))
        #expect(host.receivedKeys.isEmpty)
        receiver.sendHello()
        #expect(await eventually { !receiver.videoFrames.isEmpty })
        #expect(receiver.first { if case .welcome(let welcome) = $0 { welcome } else { nil } }?.features?.contains("keyboard") == true)
        receiver.connection.send(.key(key))
        #expect(await eventually { host.receivedKeys == [key] })
    }

    /// The no-router key goes to a tablet that asks, once it streams (an authenticated session),
    /// and stays the same across sessions.
    @Test func theDirectLinkKeyGoesToTabletsThatAsk() async throws {
        let keys = MemoryDirectKeyStore()
        let settings = StreamingSettings(bitrateKbps: 4000, port: 0, adbAutoReverse: false)
        let server = StreamServer(host: host, settings: settings, adb: nil)
        server.directKeys = keys
        try server.start(port: 0)
        defer { server.stop() }
        #expect(await eventually { server.status.listeningPort != nil })
        let port = try #require(server.status.listeningPort)
        func key(of receiver: TestReceiver) -> DirectLink? { receiver.first { if case .directLink(let link) = $0 { link } else { nil } } }

        let plain = TestReceiver(port: port)
        plain.sendHello()
        #expect(await eventually { !plain.videoFrames.isEmpty })
        #expect(key(of: plain) == nil)

        let first = TestReceiver(port: port)
        first.sendHello(features: ["clock-sync", "direct-link"])
        #expect(await eventually { key(of: first) != nil })
        let second = TestReceiver(port: port)
        second.sendHello(features: ["clock-sync", "direct-link"])
        #expect(await eventually { key(of: second) != nil })
        #expect(key(of: first) == key(of: second))
        #expect(keys.key(forDevice: "test")?.key == Hex.decode(key(of: first)?.key ?? ""))
    }

    /// A decoder that can't keep up with the display gets the rate it can decode.
    @Test func theStreamRespectsTheReceiversDecoder() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(maxFps: 30)
        #expect(await eventually { !receiver.videoFrames.isEmpty })
        #expect(receiver.first { if case .welcome(let welcome) = $0 { welcome } else { nil } }?.stream.fps == 30)
        #expect(host.preparedFor.last??.model == "SM-X730")
    }

    /// Display changes reach the receiver as CONFIGURE, and only after WELCOME.
    @Test func displayChangesAreAnnouncedToTheReceiver() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        try await Task.sleep(for: .milliseconds(50))
        await host.changeRate(to: 120)  // before HELLO: nothing to announce to
        receiver.sendHello()
        #expect(await eventually { !receiver.videoFrames.isEmpty })
        #expect(receiver.first { if case .configure(let configure) = $0 { configure } else { nil } } == nil)
        await host.changeRate(to: 60)
        #expect(await eventually { receiver.first { if case .configure(let configure) = $0 { configure } else { nil } }?.stream?.fps == 60 })
    }
}

final class Recorder<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func append(_ item: T) { lock.withLock { items.append(item) } }
    var values: [T] { lock.withLock { items } }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
