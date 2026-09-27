import CoreGraphics
import CoreVideo
import Foundation
import os
import GingaCore
import GingaProtocol
import GingaSecurity
import GingaSession
import Transport
import VideoPipeline

/// One receiver: handshake, encoder, backpressure, clock sync and control messages.
///
/// Frame path (no locks held while encoding or sending):
/// capture/synthetic queue → `frameArrived` → [skip if the socket still has 2 frames queued]
/// → `FramePacer` (latest wins) → encode queue → VideoToolbox → `sendEncoded` → socket.
///
/// `@unchecked Sendable`: all mutable state is inside `state`; the encoder and connection are
/// thread-safe.
public final class StreamConnection: @unchecked Sendable {
    public enum Phase: String, Sendable {
        case awaitingHello, pairing, preparing, streaming, closed
    }

    public struct Snapshot: Sendable {
        public var phase: Phase
        public var endpoint: String
        public var clientModel: String?
        /// The name the device's owner gave it (HELLO `device.name`), when it sends one.
        public var clientName: String?
        public var codec: VideoCodec?
        public var streamSize: PixelSize?
        public var framesSent: Int
        public var keyframesSent: Int
        public var framesSkippedForBackpressure: Int
        /// Frames above the configured stream rate (the display may compose faster, e.g. 120 Hz).
        public var framesSkippedForRateLimit: Int
        public var framesDroppedByPacer: Int
        /// Frames inside the encoder right now (0 when idle; a leak would freeze the stream).
        public var encoderFramesInFlight: Int
        public var encodeMilliseconds: StatisticSummary?
        public var sentKilobitsPerSecond: Double
        public var lastReport: ReceiverReport?
        /// The tablet can't show the stream right now (PAUSE): nothing is sent.
        public var isPaused = false
    }

    private struct State {
        var phase: Phase = .awaitingHello
        var clientModel: String?
        var clientName: String?
        var codec: VideoCodec?
        var encoder: VideoToolboxEncoder?
        var encoderSize: PixelSize?
        var announcedSize: PixelSize?
        var lastParameterSets: [Data]?
        var forceKeyframe = true
        var nextFrameId: UInt32 = 1
        var sinkToken: AnyObject?
        var framesSent = 0
        var keyframesSent = 0
        var skippedForBackpressure = 0
        var skippedForRateLimit = 0
        /// Caps the stream at its rate when the display refreshes faster.
        var cadence = FrameCadence(frameRate: 60)
        /// The stream rate.
        var frameRate: Double {
            get { cadence.frameRate }
            set { cadence.frameRate = newValue }
        }
        /// Bumped per encoder: a failure reported by an older one must not tear down the current.
        var encoderGeneration = 0
        /// Rebuild the encoder at the next frame (rate or power hint changed).
        var needsNewEncoder = false
        /// The receiver can't show video right now (CONFIGURE request "paused").
        var paused = false
        /// Most recent source frame, re-encoded when a keyframe is needed and the screen is static.
        var lastSource: SourceFrame?
        var lastSourceArrival: MediaTime?
        /// This receiver's hold on the host's frames; only touched on the main actor.
        var lease: StreamLease?
        /// When the receiver last sent anything (it PINGs every second while streaming).
        var lastReceived = MediaTime.now()
        var watchdog: DispatchSourceTimer?
        /// The receiver draws the pointer (feature `cursor`): shapes sent so far, and the sink.
        var drawsCursor = false
        var sentCursorShapes: Set<UInt32> = []
        var cursorSequence: UInt32 = 0
        var cursorToken: AnyObject?
        /// The receiver's decoder can't show more than this (HELLO `decoders[].maxFps`).
        var decoderMaxFps: Double?
        /// Wi‑Fi pairing in progress: the exchange, the HELLO to continue with, and the Mac
        /// user's prompt (withdrawn if the connection ends first).
        var pairing: PairingExchange?
        var pendingHello: Hello?
        var pairingRequest: PairingRequest?
        /// Wi‑Fi only: adapts the encoder's bitrate to the link (USB stays fixed).
        var bitrate: BitrateController?
        var bitrateKbps = 0
        var skippedAtLastReport = 0
        /// Capture time of the last frame handed to the encoder.
        var lastOffered: MediaTime?
        var trailingCheckScheduled = false
        /// Encoder hint in effect (`MaximizePowerEfficiency`), from the power policy.
        var powerEfficient = false
        var encoderPower: EncoderPowerPolicy = .automatic
        var encodeTimes = SampleWindow(capacity: 240)
        var sentBytes = RateMeter(window: .seconds(1))
        var lastReport: ReceiverReport?
    }

    public let connection: MessageConnection
    private let host: any StreamHost
    private let settings: StreamingSettings
    private let onClosed: @Sendable (StreamConnection) -> Void
    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    private let encodeQueue = DispatchQueue(label: "dev.ginga.stream.encode", qos: .userInteractive)
    private var pacer: FramePacer<EncoderInput>!

    private let trust: PeerTrust
    /// Keys for the no-router mode, handed to tablets that ask (`direct-link`, §6b).
    private let directKeys: (any DirectKeyStore)?
    private let pairingPresenter: (@MainActor (PairingRequest) -> Void)?
    /// Streaming started or pause changed (called on the main queue).
    private let onStateChange: @Sendable (StreamConnection) -> Void
    /// A loopback connection presented no (or a wrong) token: the tablet may have missed it.
    private let onUnauthorized: @Sendable () -> Void
    /// nil waits for HELLO indefinitely: on a USB accessory link the tablet app only starts once
    /// the user answers Android's "Open Ginga?" prompt.
    private let helloTimeout: Double?

    public init(
        connection: MessageConnection,
        host: any StreamHost,
        settings: StreamingSettings,
        trust: PeerTrust = .physicalLink,
        pairingPresenter: (@MainActor (PairingRequest) -> Void)? = nil,
        helloTimeout: Double?? = .none,
        onStateChange: @escaping @Sendable (StreamConnection) -> Void = { _ in },
        onUnauthorized: @escaping @Sendable () -> Void = {},
        directKeys: (any DirectKeyStore)? = nil,
        onClosed: @escaping @Sendable (StreamConnection) -> Void
    ) {
        self.directKeys = directKeys
        self.onStateChange = onStateChange
        self.onUnauthorized = onUnauthorized
        self.connection = connection
        self.host = host
        self.settings = settings
        self.trust = trust
        self.pairingPresenter = pairingPresenter
        self.helloTimeout = helloTimeout ?? settings.helloTimeoutSeconds
        self.onClosed = onClosed
        state.withLockUnchecked { $0 = Self.initialState(settings: settings, trust: trust) }
        let encodeQueue = encodeQueue
        // Two frames may be inside the encoder: one encode that overruns the frame time (8.3 ms at
        // 120 Hz) then delays the next frame instead of dropping it. Deeper would only add latency.
        self.pacer = FramePacer(maxInFlight: 2) { [weak self] input in
            encodeQueue.async { [weak self] in self?.encode(input) }
        }
    }

    private static func initialState(settings: StreamingSettings, trust: PeerTrust) -> State {
        var state = State()
        state.encoderPower = settings.encoderPower
        if case .tls = trust {
            let controller = BitrateController()
            state.bitrate = controller
            state.bitrateKbps = controller.targetKbps
        } else {
            state.bitrateKbps = settings.bitrateKbps
        }
        return state
    }

    public func start() {
        connection.setHandlers(
            onMessage: { [weak self] message in
                self?.state.withLockUnchecked { $0.lastReceived = .now() }
                self?.handle(message)
            },
            onClose: { [weak self] reason in self?.connectionClosed(reason) }
        )
        connection.start()
        guard let timeout = helloTimeout else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.state.withLockUnchecked({ $0.phase }) == .awaitingHello else { return }
            self.fail(code: "internal", message: "no HELLO within \(timeout)s", goodbye: "error")
        }
    }

    public func close(reason: String) {
        connection.send(.goodbye(Goodbye(reason: reason)))
        connection.close(reason: reason)
    }

    public var snapshot: Snapshot {
        let (dropped, inFlight) = (pacer.droppedCount, pacer.inFlightCount)  // the pacer has its own lock
        return state.withLockUnchecked { state in
            Snapshot(
                phase: state.phase, endpoint: connection.endpointDescription, clientModel: state.clientModel, clientName: state.clientName,
                codec: state.codec, streamSize: state.encoderSize ?? state.announcedSize,
                framesSent: state.framesSent, keyframesSent: state.keyframesSent,
                framesSkippedForBackpressure: state.skippedForBackpressure, framesSkippedForRateLimit: state.skippedForRateLimit,
                framesDroppedByPacer: dropped, encoderFramesInFlight: inFlight,
                encodeMilliseconds: state.encodeTimes.summary, sentKilobitsPerSecond: state.sentBytes.rate(at: .now()) * 8 / 1000,
                lastReport: state.lastReport, isPaused: state.paused
            )
        }
    }

    // MARK: Control messages

    private func handle(_ message: Message) {
        switch message {
        case .hello(let hello):
            handleHello(hello)
        case .ping(let ping):
            let received = Self.nowMicros()
            connection.send(.pong(Pong(id: ping.id, t1: ping.t1, t2: received, t3: Self.nowMicros())))
        case .keyframeRequest(let request):
            state.withLockUnchecked { $0.forceKeyframe = true }
            Log.streaming.info("stream.keyframe-requested reason=\(request.reason, privacy: .public)")
            ensureKeyframeSoon()
        case .receiverReport(let report):
            adaptBitrate(to: report)
            state.withLockUnchecked { $0.lastReport = report }
            // One line per report (1 s on USB): the tablet's view of the stream, for diagnostics.
            Log.streaming.info("stream.report frames=\(report.framesRendered ?? report.framesDecoded ?? 0) dropped=\(report.framesDropped ?? 0) decode_p50_ms=\(report.decodeMs?.p50 ?? -1) e2e_p50_ms=\(report.endToEndMs?.p50 ?? -1) e2e_p95_ms=\(report.endToEndMs?.p95 ?? -1) rtt_us=\(report.rttUs ?? -1)")
        case .configure(let configure):
            // Requests only count once the session is authenticated and streaming.
            guard state.withLockUnchecked({ $0.phase == .streaming }) else { return }
            if let orientation = configure.request?.orientation {
                let host = host
                // Via the main queue, so rotations keep their order.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { _ = Task { @MainActor in await host.requestOrientation(orientation) } }
                }
            }
            if let paused = configure.request?.paused { setPaused(paused) }
            if let refreshRate = configure.request?.refreshRate {
                // A preference only: the Mac's power setting picks the rate (60 Hz by default).
                Log.streaming.info("stream.refresh-requested hz=\(refreshRate)")
            }
        case .unknown(let raw):
            // PROTOCOL.md §1: IGNORABLE types are skipped silently; others get ERROR, and the
            // connection stays up.
            if !raw.flags.contains(.ignorable) {
                connection.send(.error(ErrorMessage(code: "unsupported", message: "message type 0x\(String(raw.type, radix: 16)) is not supported")))
            }
        case .input(let input):
            // Input only drives the Mac once the session is authenticated and streaming.
            guard state.withLockUnchecked({ $0.phase == .streaming }) else { return }
            // The main queue is strictly FIFO (separate Tasks are not), so down/move/up keep their order.
            let host = host
            DispatchQueue.main.async { MainActor.assumeIsolated { host.handleInput(input) } }
        case .key(let key):
            guard state.withLockUnchecked({ $0.phase == .streaming }) else { return }
            let host = host
            DispatchQueue.main.async { MainActor.assumeIsolated { host.handleKey(key) } }  // FIFO with INPUT
        case .pairing(let pairing):
            tabletPairing(pairing)
        case .goodbye(let goodbye):
            Log.streaming.info("stream.goodbye reason=\(goodbye.reason, privacy: .public)")
            connection.close(reason: "peer: \(goodbye.reason)")
        case .error(let error):
            Log.streaming.error("stream.peer-error code=\(error.code, privacy: .public) message=\(error.message, privacy: .public)")
        default:
            break
        }
    }

    private func handleHello(_ hello: Hello) {
        // A new HELLO on a live link: the tablet's app restarted, and a USB accessory link doesn't
        // tell us the old one went away. Start over on this connection instead of ignoring it.
        let restart = state.withLockUnchecked { [.pairing, .preparing, .streaming].contains($0.phase) }
        if restart {
            Log.streaming.info("stream.peer-restarted")
            _ = endSession(nextPhase: .awaitingHello)
            pacer.reset()
            state.withLockUnchecked { $0 = Self.initialState(settings: settings, trust: trust) }
        }
        let accepted = state.withLockUnchecked { state -> Bool in
            guard state.phase == .awaitingHello else { return false }
            state.phase = .preparing
            state.clientModel = "\(hello.device.manufacturer) \(hello.device.model)"
            state.clientName = hello.device.displayName
            return true
        }
        guard accepted else { return }
        if case .adbLoopback(let token) = trust, !LoopbackToken.matches(hello.loopbackToken, expected: token) {
            onUnauthorized()
            fail(code: "unauthorized", message: "this USB connection didn't present the token the Mac gave the Ginga app over adb", goodbye: "error")
            return
        }
        // Wi‑Fi: an unknown tablet must pair first (numeric comparison, PROTOCOL.md §6).
        if case .tls(let peer) = trust {
            guard let tablet = peer.peer() else {
                fail(code: "unsupported", message: "a client certificate is required over Wi-Fi", goodbye: "error")
                return
            }
            // Unknown here, or the tablet no longer knows this Mac: pair (both users confirm a code).
            if peer.pins.tablet(for: tablet) == nil || hello.pairingRequested == true {
                guard hello.features?.contains("pairing") == true else {
                    fail(code: "unsupported", message: "this tablet must pair over Wi-Fi, and its app doesn't support pairing", goodbye: "error")
                    return
                }
                beginPairing(hello, peer: peer, tablet: tablet)
                return
            }
        }
        negotiate(hello)
    }

    /// Version and codec, then the display, then WELCOME.
    private func negotiate(_ hello: Hello) {
        guard let version = VersionNegotiation.negotiate(remote: hello.versions) else {
            fail(code: "incompatible-version", message: "no common protocol version (Mac supports \(VersionNegotiation.supported.min)–\(VersionNegotiation.supported.max))", goodbye: "error")
            return
        }
        let mimes = Set(hello.decoders.map(\.mime))
        let preferred = settings.codec
        let fallback: VideoCodec = preferred == .hevc ? .h264 : .hevc
        guard let codec = [preferred, fallback].first(where: { mimes.contains($0.mimeType) }) else {
            fail(code: "unsupported", message: "receiver offers no HEVC or H.264 decoder", goodbye: "error")
            return
        }
        Log.streaming.info("stream.hello device=\(hello.device.model, privacy: .public) android=\(hello.device.android, privacy: .public) codec=\(codec.rawValue, privacy: .public)")

        let host = host
        let settings = settings
        let decoderMaxFps = hello.decoders.first { $0.mime == codec.mimeType }?.maxFps
        func streamRate(_ hostRate: Double) -> Double { decoderMaxFps.map { min(hostRate, max($0, 1)) } ?? hostRate }
        Task { @MainActor [weak self] in
            let lease: StreamLease
            let drawsCursor = hello.features?.contains("cursor") == true && host.supportsCursor
            do {
                let panel = ReceiverPanel(
                    model: hello.device.model, deviceId: hello.device.id, widthPx: hello.display.widthPx, heightPx: hello.display.heightPx,
                    densityDpi: hello.display.densityDpi, refreshRates: hello.display.refreshRates,
                    name: hello.device.displayName
                )
                lease = try await host.prepareForStreaming(drawsCursor: drawsCursor, receiver: panel)
            } catch {
                self?.fail(code: "internal", message: "Mac could not start the display: \(error)", goodbye: "error")
                return
            }
            guard let self else {
                lease.release()
                return
            }
            let size = host.expectedStreamSize
            let welcome = Welcome(
                version: version,
                session: String(UUID().uuidString.prefix(8)).lowercased(),
                mac: .init(name: Host.current().localizedName ?? "Mac", os: ProcessInfo.processInfo.operatingSystemVersionString, app: AppVersion.current),
                display: host.displayDescription,
                stream: StreamDescription(codec: codec.rawValue, width: size.width, height: size.height, fps: streamRate(host.frameRate), bitrateKbps: self.state.withLockUnchecked { $0.bitrateKbps }),
                features: ["clock-sync", "receiver-report", "pause", "keyboard"] + (drawsCursor ? ["cursor"] : [])
            )
            let latest = host.latestFrame
            let proceed = self.state.withLockUnchecked { state -> Bool in
                guard state.phase == .preparing else { return false }
                state.codec = codec
                state.announcedSize = size
                state.cadence = FrameCadence(frameRate: streamRate(host.frameRate), sourceRate: host.displayDescription.refreshRate)
                state.decoderMaxFps = decoderMaxFps
                state.lastSource = latest
                state.lease = lease
                state.phase = .streaming
                return true
            }
            guard proceed else {
                lease.release()  // closed while the display was starting: don't strand it
                return
            }
            self.connection.send(.welcome(welcome))
            let token = host.addFrameSink { [weak self] frame in self?.frameArrived(frame) }
            let registered = self.state.withLockUnchecked { state -> Bool in
                guard state.phase == .streaming else { return false }
                state.sinkToken = token
                return true
            }
            guard registered else {
                host.removeFrameSink(token)  // closed meanwhile; teardown didn't see this token
                return
            }
            self.startWatchdog()
            self.sendDirectLinkKey(for: hello)
            if drawsCursor, self.state.withLockUnchecked({ state -> Bool in
                guard state.phase == .streaming else { return false }
                state.drawsCursor = true  // before adding the sink, which replays where the pointer is now
                return true
            }) {
                let cursorToken = host.addCursorSink { [weak self] update in self?.cursorMoved(update) }
                let kept = self.state.withLockUnchecked { state -> Bool in
                    guard state.phase == .streaming, state.drawsCursor else { return false }
                    state.cursorToken = cursorToken
                    return true
                }
                if !kept { host.removeCursorSink(cursorToken) }
            }
            // A static screen produces no new frame: start from the latest one if none comes.
            self.ensureKeyframeSoon()
            self.onStateChange(self)
            Log.streaming.info("stream.started size=\(size.description, privacy: .public) fps=\(streamRate(host.frameRate)) kbps=\(settings.bitrateKbps)")
        }
    }

    // MARK: Video

    private func frameArrived(_ frame: SourceFrame) {
        enum Decision { case send, skip, ignore }
        let decision = state.withLockUnchecked { state -> Decision in
            guard state.phase == .streaming else { return .ignore }
            state.lastSource = frame
            state.lastSourceArrival = .now()
            guard !state.paused else { return .ignore }
            guard state.cadence.admits(frame.captureTime) else {
                state.skippedForRateLimit += 1
                return .skip
            }
            guard connection.canAcceptVideo else {
                state.skippedForBackpressure += 1
                return .skip
            }
            state.cadence.take(frame.captureTime)
            state.lastOffered = frame.captureTime
            return .send
        }
        switch decision {
        case .send: pacer.offer(EncoderInput(pixelBuffer: frame.pixelBuffer, captureTime: frame.captureTime))
        case .skip: scheduleTrailingCheck()
        case .ignore: break
        }
    }

    /// A skipped frame may be the last one before the screen goes still (the final position of a
    /// window, the last typed character). If nothing newer arrives within a frame interval, the
    /// latest frame is sent after all, so the tablet never keeps a stale picture.
    private func scheduleTrailingCheck() {
        let interval = state.withLockUnchecked { state -> Double? in
            guard !state.trailingCheckScheduled else { return nil }
            state.trailingCheckScheduled = true
            return 1 / max(state.frameRate, 1)
        }
        guard let interval else { return }
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + interval * 1.5) { [weak self] in
            self?.sendTrailingFrame()
        }
    }

    private func sendTrailingFrame() {
        enum Outcome { case send(SourceFrame), wait, done }
        let outcome = state.withLockUnchecked { state -> Outcome in
            state.trailingCheckScheduled = false
            guard state.phase == .streaming, !state.paused, let last = state.lastSource, let arrival = state.lastSourceArrival else { return .done }
            if let offered = state.lastOffered, offered >= last.captureTime { return .done }  // the latest was sent
            // Still changing, or the link is still busy: look again shortly.
            if MediaTime.now() - arrival < .seconds(1 / max(state.frameRate, 1)) || !connection.canAcceptVideo { return .wait }
            state.cadence.take(last.captureTime)
            state.lastOffered = last.captureTime
            return .send(last)
        }
        switch outcome {
        case .send(let frame): pacer.offer(EncoderInput(pixelBuffer: frame.pixelBuffer, captureTime: frame.captureTime))
        case .wait: scheduleTrailingCheck()
        case .done: break
        }
    }

    /// Runs on the encode queue.
    private func encode(_ input: EncoderInput) {
        let size = PixelSize(width: CVPixelBufferGetWidth(input.pixelBuffer), height: CVPixelBufferGetHeight(input.pixelBuffer))
        let (encoder, forceKeyframe, streaming) = state.withLockUnchecked { state -> (VideoToolboxEncoder?, Bool, Bool) in
            defer { state.forceKeyframe = false }
            let reusable = state.encoderSize == size && !state.needsNewEncoder
            return (reusable ? state.encoder : nil, state.forceKeyframe, state.phase == .streaming)
        }
        guard streaming else {  // closed meanwhile: never build a hardware encoder for nobody
            pacer.completed()
            return
        }
        let active = encoder ?? makeEncoder(size: size)
        guard let active else {
            pacer.completed()
            return
        }
        var input = input
        input.forceKeyframe = input.forceKeyframe || forceKeyframe || encoder == nil
        active.encode(input)
    }

    private func makeEncoder(size: PixelSize) -> VideoToolboxEncoder? {
        let onBattery = PowerSource.isOnBattery
        let (codec, frameRate, previous, powerEfficient, bitrateKbps, generation) = state.withLockUnchecked { state in
            state.powerEfficient = state.encoderPower.maximizesEfficiency(onBattery: onBattery)
            state.encoderGeneration += 1
            state.needsNewEncoder = false
            defer { state.encoder = nil }  // taken out: torn down below, never under the lock
            return (state.codec, state.frameRate, state.encoder, state.powerEfficient, state.bitrateKbps, state.encoderGeneration)
        }
        // The previous encoder may still hold frames (up to 2 in flight). Let it finish them: their
        // callbacks send them, in order, before the new encoder's first frame, and hand the pacer
        // its slots back. Invalidating first would lose those callbacks and freeze the pacer.
        previous?.flush()
        previous?.invalidate()
        guard let codec else { return nil }
        do {
            let encoder = try VideoToolboxEncoder(
                configuration: EncoderConfiguration(
                    codec: codec, size: size, frameRate: frameRate, bitrateKbps: bitrateKbps,
                    maximizePowerEfficiency: powerEfficient
                )
            ) { [weak self] event in self?.encoderEvent(event, generation: generation, size: size) }
            state.withLockUnchecked { state in
                state.encoder = encoder
                state.encoderSize = size
                state.lastParameterSets = nil
            }
            Log.streaming.info("stream.encoder size=\(size.description, privacy: .public) codec=\(codec.rawValue, privacy: .public) power_efficient=\(powerEfficient)")
            return encoder
        } catch {
            Log.streaming.error("stream.encoder-failed reason=\(error.description, privacy: .public)")
            fail(code: "internal", message: error.description, goodbye: "error")
            return nil
        }
    }

    private func encoderEvent(_ event: EncoderEvent, generation: Int, size: PixelSize) {
        defer { pacer.completed() }
        switch event {
        case .frame(let frame):
            sendEncoded(frame, size: size)
        case .dropped:
            break
        case .failed(let error):
            Log.streaming.error("stream.encode-failed reason=\(error.description, privacy: .public)")
            // Only the current encoder's failure matters; rebuild it at the next frame.
            let failed: VideoToolboxEncoder? = state.withLockUnchecked { state in
                guard state.encoderGeneration == generation else { return nil }
                defer {
                    state.encoder = nil
                    state.encoderSize = nil
                    state.forceKeyframe = true
                }
                return state.encoder
            }
            // Never tear VideoToolbox down under the lock or on its own callback thread.
            if let failed { encodeQueue.async { failed.invalidate() } }
        }
    }

    /// `size` is the size of the encoder that produced the frame.
    private func sendEncoded(_ frame: EncodedFrame, size: PixelSize) {
        let plan = state.withLockUnchecked { state -> (frameId: UInt32, format: StreamFormat?, announce: StreamDescription?)? in
            guard state.phase == .streaming, let codec = state.codec else { return nil }
            var format: StreamFormat?
            var announce: StreamDescription?
            if frame.isKeyframe, let sets = frame.parameterSets, sets != state.lastParameterSets {
                format = StreamFormat(codec: codec.rawValue, width: size.width, height: size.height, parameterSets: sets)
                state.lastParameterSets = sets
                if state.announcedSize != size {
                    announce = StreamDescription(codec: codec.rawValue, width: size.width, height: size.height, fps: state.frameRate, bitrateKbps: state.bitrateKbps)
                    state.announcedSize = size
                }
            }
            let frameId = state.nextFrameId
            state.nextFrameId &+= 1
            state.framesSent += 1
            if frame.isKeyframe { state.keyframesSent += 1 }
            state.encodeTimes.add(frame.encodeDuration.inMilliseconds)
            state.sentBytes.record(at: .now(), amount: Double(frame.data.count))
            return (frameId, format, announce)
        }
        guard let plan else { return }
        if let announce = plan.announce { connection.send(.configure(Configure(stream: announce))) }
        if let format = plan.format { connection.send(.streamFormat(format)) }
        connection.send(.videoFrame(VideoFrame(
            frameId: plan.frameId,
            captureTimeUs: frame.captureTime.nanoseconds / 1000,
            encodeDurationUs: UInt32(clamping: frame.encodeDuration.totalNanoseconds / 1000),
            isKeyframe: frame.isKeyframe,
            data: frame.data
        )))
    }

    // MARK: Teardown

    private func fail(code: String, message: String, goodbye: String) {
        Log.streaming.error("stream.fail code=\(code, privacy: .public) message=\(message, privacy: .public)")
        connection.send(.error(ErrorMessage(code: code, message: message)))
        connection.send(.goodbye(Goodbye(reason: goodbye)))
        connection.close(reason: message)
    }

    private func connectionClosed(_ reason: MessageConnection.CloseReason) {
        let summary = endSession(nextPhase: .closed)
        Log.streaming.info("stream.closed reason=\(String(describing: reason), privacy: .public) \(summary, privacy: .public)")
        onClosed(self)
    }

    /// Releases what the session holds (frame and cursor sinks, lease, encoder, prompt, watchdog)
    /// and moves to `nextPhase`. Returns the session summary for the log.
    private func endSession(nextPhase: Phase) -> String {
        let pacerDropped = pacer.droppedCount  // read before taking `state` (no nested locks)
        let (tokens, encoder, summary, lease, wasStreaming, pairingRequest, watchdog) = state.withLockUnchecked { state -> ((AnyObject?, AnyObject?), VideoToolboxEncoder?, String, StreamLease?, Bool, PairingRequest?, DispatchSourceTimer?) in
            let wasStreaming = state.phase == .streaming
            state.phase = nextPhase
            defer {
                state.sinkToken = nil
                state.encoder = nil
                state.lease = nil
                state.pairingRequest = nil
                state.cursorToken = nil
                state.watchdog = nil
                // The receiver forgets its shapes when a session ends (§3.3b); a new HELLO on this
                // link must get them again, or it has nothing to draw the pointer with.
                state.drawsCursor = false
                state.sentCursorShapes = []
                state.cursorSequence = 0
            }
            let encode = state.encodeTimes.summary.map { String(format: "%.1f/%.1f/%.1f", $0.p50, $0.p95, $0.max) } ?? "-"
            let summary = "sent=\(state.framesSent) keyframes=\(state.keyframesSent) skipped_rate=\(state.skippedForRateLimit) skipped_backpressure=\(state.skippedForBackpressure) cursor_messages=\(state.cursorSequence) pacer_dropped=\(pacerDropped) encode_ms_p50/p95/max=\(encode)"
            return ((state.sinkToken, state.cursorToken), state.encoder, summary, state.lease, wasStreaming, state.pairingRequest, state.watchdog)
        }
        watchdog?.cancel()

        pairingRequest?.end()  // withdraw the Mac's prompt
        encoder?.invalidate()
        let host = host
        // On the main queue, after any input this receiver sent (same FIFO).
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let token = tokens.0 { host.removeFrameSink(token) }
                if let cursorToken = tokens.1 { host.removeCursorSink(cursorToken) }
                lease?.release()
                if wasStreaming { host.inputEnded() }
            }
        }
        return summary
    }

    /// While streaming, a receiver that says nothing for `silenceTimeout` is gone (its app died,
    /// or a USB accessory link went quiet without closing): end the session, so a direct-USB link
    /// is offered afresh. Receivers PING every second, paused ones too.
    nonisolated(unsafe) static var silenceTimeout: Duration = .seconds(5)  // tests shorten it

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let silent = self.state.withLockUnchecked { $0.phase == .streaming && MediaTime.now() - $0.lastReceived > Self.silenceTimeout }
            if silent { self.connection.close(reason: "nothing from the receiver for \(Self.silenceTimeout)") }
        }
        let kept = state.withLockUnchecked { state -> Bool in
            guard state.phase == .streaming else { return false }
            state.lastReceived = .now()
            state.watchdog = timer
            return true
        }
        if kept { timer.resume() }
    }

    // MARK: Pairing (Wi‑Fi)

    private func beginPairing(_ hello: Hello, peer: TLSPeer, tablet: CertificateFingerprint) {
        let exchange = PairingExchange(mac: peer.local, tablet: tablet)
        state.withLockUnchecked { state in
            state.phase = .pairing
            state.pendingHello = hello
            state.pairing = exchange
        }
        connection.send(.pairing(exchange.start(macName: peer.macName)))
        Log.streaming.info("stream.pairing-required tablet=\(hello.device.manufacturer, privacy: .public) \(hello.device.model, privacy: .public)")
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) { [weak self] in
            guard let self, self.state.withLockUnchecked({ $0.phase == .pairing }) else { return }
            self.rejectPairing(reason: "pairing timed out")
        }
    }

    private func tabletPairing(_ message: Pairing) {
        let actions = state.withLockUnchecked { state -> [PairingExchange.Action] in
            guard state.phase == .pairing, var exchange = state.pairing else { return [] }
            defer { state.pairing = exchange }
            return exchange.receive(message)
        }
        perform(actions)
    }

    private func macPairingDecision(_ accepted: Bool) {
        let actions = state.withLockUnchecked { state -> [PairingExchange.Action] in
            guard state.phase == .pairing, var exchange = state.pairing else { return [] }
            defer { state.pairing = exchange }
            return exchange.macUserAnswered(accepted)
        }
        perform(actions)
    }

    private func perform(_ actions: [PairingExchange.Action]) {
        for action in actions {
            switch action {
            case .send(let message):
                connection.send(.pairing(message))
            case .askMacUser(let code):
                askMacUser(code: code)
            case .pair:
                completePairing()
            case .reject(let reason):
                rejectPairing(reason: reason)
            case .macUserDeclined:
                rejectPairing(reason: "pairing declined on the Mac", goodbye: "user")
            case .tabletDeclined:
                Log.streaming.info("stream.pairing-declined-on-tablet")
                connection.close(reason: "pairing declined on the tablet")
            }
        }
    }

    /// Both nonces are in: the Mac's user compares the code with the tablet's.
    private func askMacUser(code: String) {
        guard let presenter = pairingPresenter else {
            rejectPairing(reason: "nobody can confirm pairing on this Mac")
            return
        }
        let tabletName = state.withLockUnchecked { $0.pendingHello.map(\.device.label) } ?? "Tablet"
        let request = PairingRequest(tabletName: tabletName, code: code) { [weak self] accepted in
            self?.macPairingDecision(accepted)
        }
        let open = state.withLockUnchecked { state -> Bool in
            guard state.phase == .pairing else { return false }
            state.pairingRequest = request
            return true
        }
        guard open else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { presenter(request) } }
    }

    private func completePairing() {
        guard case .tls(let peer) = trust else { return }
        let pending = state.withLockUnchecked { state -> (Hello, CertificateFingerprint)? in
            guard state.phase == .pairing, let hello = state.pendingHello, let tablet = state.pairing?.tablet else { return nil }
            state.phase = .preparing
            state.pendingHello = nil
            state.pairing = nil
            state.pairingRequest = nil
            return (hello, tablet)
        }
        guard let (hello, tablet) = pending else { return }
        do {
            try peer.pins.add(PairedTablet(fingerprint: tablet, name: hello.device.label))
        } catch {
            fail(code: "internal", message: "could not store the pairing: \(error)", goodbye: "error")
            return
        }
        Log.streaming.info("stream.paired fingerprint=\(tablet.hex, privacy: .public)")
        connection.send(.pairing(Pairing(state: .paired, name: peer.macName)))
        negotiate(hello)
    }

    private func rejectPairing(reason: String, goodbye: String = "error") {
        guard state.withLockUnchecked({ $0.phase == .pairing }) else { return }
        Log.streaming.info("stream.pairing-rejected reason=\(reason, privacy: .public)")
        connection.send(.pairing(Pairing(state: .rejected)))
        connection.send(.goodbye(Goodbye(reason: goodbye)))
        connection.close(reason: reason)
    }

    // MARK: Display changes

    /// The display was reconfigured (mode, orientation, or refresh rate on a power-source change):
    /// announce it (CONFIGURE), and when the rate changed, rebuild the encoder for it and tell
    /// the tablet, so its panel can follow. Ignored until WELCOME went out.
    /// - Parameter latest: the host's latest frame. When capture restarted (new size or
    ///   orientation) it is nil, so a frame of the old configuration is never re-encoded as a
    ///   keyframe; after a pure move it is still valid.
    func displayChanged(_ display: DisplayDescription, frameRate hostRate: Double, latest: SourceFrame?) {
        let update = state.withLockUnchecked { state -> Configure? in
            guard state.phase == .streaming else { return nil }
            let frameRate = state.decoderMaxFps.map { min(hostRate, max($0, 1)) } ?? hostRate
            state.lastSource = latest
            if latest == nil { state.lastSourceArrival = nil }
            state.cadence.sourceRate = display.refreshRate
            guard abs(state.frameRate - frameRate) > 0.5, let codec = state.codec,
                  let size = state.encoderSize ?? state.announcedSize else { return Configure(display: display, stream: nil) }
            state.frameRate = frameRate
            state.cadence.reset()
            state.needsNewEncoder = true  // next frame: new encoder (ExpectedFrameRate follows), keyframe
            let stream = StreamDescription(codec: codec.rawValue, width: size.width, height: size.height, fps: frameRate, bitrateKbps: state.bitrateKbps)
            return Configure(display: display, stream: stream)
        }
        guard let update else { return }
        connection.send(.configure(update))
        if let stream = update.stream { Log.streaming.info("stream.rate-changed fps=\(stream.fps)") }
    }

    // MARK: Adaptive bitrate (Wi‑Fi)

    private func adaptBitrate(to report: ReceiverReport) {
        let change = state.withLockUnchecked { state -> (VideoToolboxEncoder?, Int)? in
            guard state.phase == .streaming, var controller = state.bitrate else { return nil }
            let skipped = state.skippedForBackpressure - state.skippedAtLastReport
            state.skippedAtLastReport = state.skippedForBackpressure
            let sample = BitrateController.Sample(
                time: .now(), endToEndP50Milliseconds: report.endToEndMs?.p50,
                framesDropped: report.framesDropped ?? 0, framesSkippedForBackpressure: skipped
            )
            defer { state.bitrate = controller }
            guard let target = controller.update(sample) else { return nil }
            state.bitrateKbps = target
            return (state.encoder, target)
        }
        guard let (encoder, kbps) = change else { return }
        encoder?.setBitrate(kbps: kbps)  // live, no keyframe
        Log.streaming.info("stream.bitrate kbps=\(kbps)")
    }

    // MARK: Direct link (§6b)

    /// Only over an authenticated session: this connection got past the token, the approval or
    /// the pinning before streaming started.
    private func sendDirectLinkKey(for hello: Hello) {
        guard hello.features?.contains("direct-link") == true, let directKeys else { return }
        do {
            let key = try directKeys.keyCreatingIfNeeded(deviceId: hello.device.id, name: "\(hello.device.manufacturer) \(hello.device.model)")
            connection.send(.directLink(DirectLink(keyId: Hex.encode(key.keyId), key: Hex.encode(key.key))))
            Log.streaming.info("stream.direct-link-key-sent")
        } catch {
            Log.streaming.error("stream.direct-link-key-failed reason=\(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Cursor side channel (§3.3b)

    /// The pointer moved (main actor): its shape once per session, then its position.
    private func cursorMoved(_ update: CursorUpdate) {
        let messages = state.withLockUnchecked { state -> [Message] in
            guard state.phase == .streaming, state.drawsCursor, !state.paused else { return [] }
            var messages: [Message] = []
            if let shape = update.shape, state.sentCursorShapes.insert(shape.id).inserted {
                Log.streaming.info("stream.cursor-shape id=\(shape.id) size=\(shape.width)x\(shape.height) png_bytes=\(shape.png.count)")
                messages.append(.cursorShape(CursorShape(
                    shapeId: shape.id, width: UInt16(clamping: shape.width), height: UInt16(clamping: shape.height),
                    hotspotX: UInt16(clamping: shape.hotspotX), hotspotY: UInt16(clamping: shape.hotspotY), png: shape.png
                )))
            }
            state.cursorSequence &+= 1
            messages.append(.cursor(CursorPosition(
                sequence: state.cursorSequence, timeUs: update.time.nanoseconds / 1000, x: update.x, y: update.y,
                visible: update.visible && update.shape != nil, shapeId: update.shape?.id ?? 0
            )))
            return messages
        }
        messages.forEach(connection.send)
    }

    // MARK: Pause, keyframes, power

    /// The receiver can't show video (app in the background, screen off): stop sending frames
    /// and let the host stop capturing. On resume a keyframe follows promptly.
    private func setPaused(_ paused: Bool) {
        let (changed, lease) = state.withLockUnchecked { state -> (Bool, StreamLease?) in
            guard state.phase == .streaming, state.paused != paused else { return (false, nil) }
            state.paused = paused
            if !paused {
                state.forceKeyframe = true
                state.cadence.reset()
            }
            return (true, state.lease)
        }
        guard changed else { return }
        Log.streaming.info("stream.paused value=\(paused)")
        // The main queue keeps pause/resume in order (separate Tasks would not).
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                lease?.setPaused(paused)
                guard let self else { return }
                if !paused { self.ensureKeyframeSoon() }
                self.onStateChange(self)
            }
        }
    }

    /// Whether the connection is over (its GOODBYE, if any, was flushed first).
    public var isClosed: Bool { state.withLockUnchecked { $0.phase == .closed } }
    /// Whether this receiver is streaming (authenticated, WELCOME sent).
    public var isStreaming: Bool { state.withLockUnchecked { $0.phase == .streaming } }
    public var isPaused: Bool { state.withLockUnchecked { $0.paused } }
    /// Whether the receiver connected over Wi‑Fi (TLS) rather than a physical link.
    public var isWiFi: Bool {
        if case .tls = trust { return true }
        return false
    }
    /// The tablet's certificate on Wi‑Fi (nil on USB).
    public var peerFingerprint: CertificateFingerprint? {
        if case .tls(let peer) = trust { return peer.peer() }
        return nil
    }

    /// If no new frame gets encoded shortly (static screen), re-encode the latest one so a
    /// pending keyframe (new receiver, keyframe request, resume) is never left waiting.
    private func ensureKeyframeSoon() {
        let delay = max(0.05, 2 / max(state.withLockUnchecked { $0.frameRate }, 1))
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.resendLatestIfStillWaiting()
        }
    }

    private func resendLatestIfStillWaiting() {
        let source = state.withLockUnchecked { state -> SourceFrame? in
            guard state.phase == .streaming, !state.paused, state.forceKeyframe else { return nil }
            return state.lastSource
        }
        guard let source else { return }
        state.withLockUnchecked { $0.lastOffered = source.captureTime }
        Log.streaming.debug("stream.keyframe-from-latest")
        // Stamped now: it's a repeat, not a new composition, and latency stats should say so.
        pacer.offer(EncoderInput(pixelBuffer: source.pixelBuffer, captureTime: .now(), forceKeyframe: true))
    }

    /// The encoder power policy changed in the settings.
    public func setEncoderPower(_ policy: EncoderPowerPolicy) {
        state.withLockUnchecked { $0.encoderPower = policy }
        powerSourceChanged()
    }

    /// The Mac switched between battery and AC: rebuild the encoder if its power hint changes.
    public func powerSourceChanged() {
        let onBattery = PowerSource.isOnBattery
        let (stale, efficient) = state.withLockUnchecked { state -> (Bool, Bool) in
            let efficient = state.encoderPower.maximizesEfficiency(onBattery: onBattery)
            guard state.phase == .streaming, state.encoder != nil, state.powerEfficient != efficient else { return (false, efficient) }
            state.needsNewEncoder = true  // the next frame creates a new encoder (and a keyframe)
            return (true, efficient)
        }
        if stale { Log.streaming.info("stream.encoder-power-changed power_efficient=\(efficient)") }
    }

    static func nowMicros() -> UInt64 {
        MediaTime.now().nanoseconds / 1000
    }
}
