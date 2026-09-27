import CoreGraphics
import CoreVideo
import DisplayCapture
import Foundation
import os
import GingaCore
import GingaProtocol
import GingaSession
import VirtualDisplay

extension Log {
    public static let streaming = Logger(subsystem: subsystem, category: "streaming")
}

/// A frame to stream. `@unchecked Sendable`: IOSurface-backed buffers are immutable once produced.
public struct SourceFrame: @unchecked Sendable {
    public var pixelBuffer: CVPixelBuffer
    public var captureTime: MediaTime
    public var pixelSize: PixelSize

    public init(pixelBuffer: CVPixelBuffer, captureTime: MediaTime, pixelSize: PixelSize) {
        self.pixelBuffer = pixelBuffer
        self.captureTime = captureTime
        self.pixelSize = pixelSize
    }
}

/// The pointer, for receivers that draw it themselves (PROTOCOL.md §3.3b).
public struct CursorUpdate: Sendable {
    /// The hotspot, normalized to 0…65535 across the display.
    public var x: UInt16
    public var y: UInt16
    /// False while the pointer is on another display.
    public var visible: Bool
    public var shape: CursorTracker.Shape?
    public var time: MediaTime

    public init(x: UInt16, y: UInt16, visible: Bool, shape: CursorTracker.Shape?, time: MediaTime = .now()) {
        self.x = x
        self.y = y
        self.visible = visible
        self.shape = shape
        self.time = time
    }
}

/// The receiver's panel, from HELLO: a display created for it takes its shape.
public struct ReceiverPanel: Sendable, Equatable {
    public var model: String
    public var deviceId: String
    public var widthPx: Int
    public var heightPx: Int
    public var densityDpi: Int
    public var refreshRates: [Double]
    /// The device's own name (HELLO `device.name`): what the display is called when Ginga has no
    /// profile for the model.
    public var name: String?

    public init(model: String, deviceId: String, widthPx: Int, heightPx: Int, densityDpi: Int, refreshRates: [Double], name: String? = nil) {
        self.name = name
        self.model = model
        self.deviceId = deviceId
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.densityDpi = densityDpi
        self.refreshRates = refreshRates
    }
}

/// What a streaming session needs from the Mac side. The real host is the virtual display
/// session; tests and `ginga serve --synthetic` use generated frames.
@MainActor
public protocol StreamHost: AnyObject {
    /// Makes sure frames flow for one more receiver (creates the display, enables capture) and
    /// returns its lease. Frames stop, and a display created for tablets goes away, once no
    /// active lease is left.
    /// - Parameter drawsCursor: the receiver draws the pointer itself (cursor sinks); while every
    ///   active receiver does, the pointer stays out of the video.
    func prepareForStreaming(drawsCursor: Bool, receiver: ReceiverPanel?) async throws -> StreamLease
    /// Whether this host can report the pointer (`addCursorSink`).
    var supportsCursor: Bool { get }
    /// Pointer updates, at most once per display refresh; the latest one is delivered right away.
    func addCursorSink(_ sink: @escaping @MainActor (CursorUpdate) -> Void) -> AnyObject
    func removeCursorSink(_ token: AnyObject)
    /// The most recent frame, so a new receiver (or a keyframe request) doesn't have to wait for
    /// the screen to change.
    var latestFrame: SourceFrame? { get }
    /// Called with the new description when the display is reconfigured (mode, orientation).
    /// Set by the `StreamServer`, which forwards it to its receivers.
    var onDisplayChange: (@MainActor (DisplayDescription) -> Void)? { get set }
    var displayDescription: DisplayDescription { get }
    /// Expected stream size (capture output) for WELCOME; actual frames may differ after changes.
    var expectedStreamSize: PixelSize { get }
    var frameRate: Double { get }
    func addFrameSink(_ sink: @escaping @Sendable (SourceFrame) -> Void) -> AnyObject
    func removeFrameSink(_ token: AnyObject)
    /// The receiver asked for a different orientation ("landscape" / "portrait").
    func requestOrientation(_ orientation: String) async
    /// Input from the receiver (M5).
    func handleInput(_ input: InputMessage)
    /// A key from a keyboard attached to the receiver (§3.3c).
    func handleKey(_ key: KeyMessage)
    /// The receiver that sent input is gone: release anything it still holds (a drag, a scroll, keys).
    func inputEnded()
}

extension StreamHost {
    public func prepareForStreaming(drawsCursor: Bool = false) async throws -> StreamLease {
        try await prepareForStreaming(drawsCursor: drawsCursor, receiver: nil)
    }
}

/// One receiver's hold on the host's frames. Pausing it (app in the background) or releasing it
/// (connection closed) withdraws that receiver's demand; release is idempotent.
@MainActor
public final class StreamLease {
    public private(set) var isPaused = false
    public private(set) var isReleased = false
    /// The receiver draws the pointer itself.
    public let drawsCursor: Bool
    private let changed: @MainActor () -> Void

    init(drawsCursor: Bool = false, changed: @escaping @MainActor () -> Void) {
        self.drawsCursor = drawsCursor
        self.changed = changed
    }

    var isActive: Bool { !isReleased && !isPaused }

    public func setPaused(_ paused: Bool) {
        guard !isReleased, paused != isPaused else { return }
        isPaused = paused
        changed()
    }

    public func release() {
        guard !isReleased else { return }
        isReleased = true
        changed()
    }
}

// MARK: - Virtual display host

/// Streams the virtual display through the existing `DisplaySession` (layers 1+2).
@MainActor
public final class DisplayStreamHost: StreamHost {
    public let session: DisplaySession
    public var inputHandler: (@MainActor (InputMessage, ActiveVirtualDisplay) -> Void)?
    public var inputEndHandler: (@MainActor () -> Void)?
    public var keyHandler: (@MainActor (KeyMessage) -> Void)?
    private var tokens: [ObjectIdentifier: FrameSinkRegistry.Token] = [:]
    public var onDisplayChange: (@MainActor (DisplayDescription) -> Void)?
    private var leases: [StreamLease] = []
    /// Capture-demand changes, applied in order.
    private var demandTask: Task<Void, Never>?
    private var removal: Task<Void, Never>?

    public init(session: DisplaySession) {
        self.session = session
        session.onDisplayEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .activated, .reconfigured:
                self.onDisplayChange?(self.displayDescription)
            case .deactivated, .lost:
                break
            }
        }
    }

    /// Whether some receiver holds (or is setting up) the display.
    public var hasReceivers: Bool { leases.contains { !$0.isReleased } }

    public func prepareForStreaming(drawsCursor: Bool, receiver: ReceiverPanel?) async throws -> StreamLease {
        removal?.cancel()
        removal = nil
        // Counted before the first await, so a receiver that leaves meanwhile is still seen.
        let lease = StreamLease(drawsCursor: drawsCursor && supportsCursor) { [weak self] in self?.leasesChanged() }
        leases.append(lease)
        do {
            // Queued behind any display operation in flight: if the lingering display is being
            // removed right now, the removal completes and a fresh display replaces it.
            try await session.ensureDisplay(owner: .stream, tabletDisplay: receiver.flatMap(tabletDisplay(for:)))
        } catch {
            lease.release()
            throw error
        }
        leasesChanged()
        return lease
    }

    private func leasesChanged() {
        leases.removeAll { $0.isReleased }
        let active = leases.filter(\.isActive)
        // The pointer leaves the video only while every receiver draws it (a mixed pair during a
        // hand-over keeps it in the video; the one that draws it then shows two, briefly).
        session.setCursorInCapture(!(!active.isEmpty && active.allSatisfy(\.drawsCursor)))
        if active.contains(where: \.drawsCursor) {
            cursorTracker.scale = streamScale
            cursorTracker.start()
        } else {
            cursorTracker.stop()
            lastCursor = nil
        }
        let wanted = !active.isEmpty
        let previous = demandTask
        demandTask = Task { [session] in
            await previous?.value
            await session.setCaptureDemand(.stream, wanted)
        }
        if leases.isEmpty { scheduleRemoval() }
    }

    /// The display for another device than the configured one (Tab S9 FE+, a phone…): its
    /// profile if Ginga knows the model, else one derived from what it reported.
    func tabletDisplay(for receiver: ReceiverPanel) -> VirtualDisplayConfiguration? {
        guard session.configuration.streaming.matchTabletDisplay else { return nil }
        let profile = DeviceProfile.matching(model: receiver.model) ?? DeviceProfile.generic(
            model: receiver.model, widthPx: receiver.widthPx, heightPx: receiver.heightPx,
            densityDpi: receiver.densityDpi, refreshRates: receiver.refreshRates, name: receiver.name
        )
        if profile.id == session.configuration.display.profileID { return nil }  // already configured for it
        if profile.id == "auto", receiver.widthPx < 640 || receiver.heightPx < 400 { return nil }  // nonsense panel
        var display = profile.configuration()
        if profile.id == "auto" {  // one identity per device, so macOS remembers each one's arrangement
            display.identity.serialNumber = receiver.deviceId.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        }
        Log.streaming.info("stream.display-for-tablet profile=\(profile.id, privacy: .public) model=\(receiver.model, privacy: .public)")
        return display
    }

    /// Like Sidecar: a display that only existed for tablets goes away with the last one (after a
    /// grace period for reconnects), so no window is stranded on an invisible screen.
    private func scheduleRemoval() {
        guard session.displayOwner == .stream, let linger = session.configuration.streaming.displayLingerSeconds else { return }
        removal?.cancel()
        let delay = Duration.milliseconds(Int64(min(max(0, linger), 86_400) * 1000))
        removal = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.leases.isEmpty, self.session.displayOwner == .stream else { return }
            Log.streaming.info("stream.display-removed-after-disconnect linger_s=\(linger)")
            self.removal = nil
            await self.session.stopDisplay()
        }
    }

    public var latestFrame: SourceFrame? {
        session.frames.latest.map { SourceFrame(pixelBuffer: $0.pixelBuffer, captureTime: $0.displayTime, pixelSize: $0.pixelSize) }
    }

    public var displayDescription: DisplayDescription {
        guard let active = session.activeDisplay else {
            return DisplayDescription(id: 0, name: session.configuration.display.name, looksLike: PixelDimensions(width: 0, height: 0), hiDPI: true, refreshRate: 60, orientation: "landscape")
        }
        let size = active.mode?.size ?? active.plan.target.size
        return DisplayDescription(
            id: active.displayID,
            name: active.configuration.name,
            looksLike: PixelDimensions(width: size.width, height: size.height),
            hiDPI: active.mode?.isHiDPI ?? active.configuration.hiDPI,
            refreshRate: active.mode?.refreshRate ?? active.configuration.refreshRate,
            orientation: size.isPortrait ? "portrait" : "landscape"
        )
    }

    public var expectedStreamSize: PixelSize {
        guard let active = session.activeDisplay else { return session.configuration.display.panel.nativePixels }
        let capture = session.configuration.capture.captureConfiguration(for: active)
        return CaptureSizing.outputSize(displayPixels: active.pixelSize, maxOutputSize: capture.maxOutputSize)
    }

    /// The stream rate (the display may compose faster, see `CaptureSettings.maxFrameRate`).
    public var frameRate: Double {
        let refresh = session.activeDisplay?.mode?.refreshRate ?? session.effectiveDisplay.refreshRate
        return session.configuration.capture.streamFrameRate(displayRefresh: refresh)
    }

    public func addFrameSink(_ sink: @escaping @Sendable (SourceFrame) -> Void) -> AnyObject {
        let token = SinkToken()
        tokens[ObjectIdentifier(token)] = session.frames.add { frame in
            sink(SourceFrame(pixelBuffer: frame.pixelBuffer, captureTime: frame.displayTime, pixelSize: frame.pixelSize))
        }
        return token
    }

    public func removeFrameSink(_ token: AnyObject) {
        if let registryToken = tokens.removeValue(forKey: ObjectIdentifier(token)) {
            session.frames.remove(registryToken)
        }
    }

    public func requestOrientation(_ orientation: String) async {
        guard let wanted = DisplayOrientation(rawValue: orientation), session.configuration.display.orientation != wanted else { return }
        var configuration = session.configuration
        configuration.display.orientation = wanted
        do {
            try await session.apply(configuration)
            Log.streaming.info("stream.orientation-applied orientation=\(orientation, privacy: .public)")
        } catch {
            Log.streaming.error("stream.orientation-failed reason=\(String(describing: error), privacy: .public)")
        }
    }

    public func handleInput(_ input: InputMessage) {
        guard let active = session.activeDisplay else { return }
        inputHandler?(input, active)
    }

    // MARK: Cursor side channel

    public var supportsCursor: Bool { CursorTracker.isSupported }
    private lazy var cursorTracker = CursorTracker(scale: 2) { [weak self] sample in self?.cursorMoved(sample) }
    private var cursorSinks: [ObjectIdentifier: @MainActor (CursorUpdate) -> Void] = [:]
    private var lastCursor: CursorUpdate?
    private var pendingCursor: CursorUpdate?
    private var lastCursorSent: MediaTime?
    private var cursorFlushScheduled = false

    /// Stream pixels per display point (shape images are drawn at this scale).
    private var streamScale: CGFloat {
        guard let active = session.activeDisplay, active.bounds.width > 0 else { return 2 }
        return CGFloat(expectedStreamSize.width) / active.bounds.width
    }

    public func addCursorSink(_ sink: @escaping @MainActor (CursorUpdate) -> Void) -> AnyObject {
        let token = SinkToken()
        cursorSinks[ObjectIdentifier(token)] = sink
        if let lastCursor { sink(lastCursor) }  // where the pointer is now, before it moves
        return token
    }

    public func removeCursorSink(_ token: AnyObject) {
        cursorSinks.removeValue(forKey: ObjectIdentifier(token))
    }

    private func cursorMoved(_ sample: CursorTracker.Sample) {
        guard let bounds = session.activeDisplay?.bounds, bounds.width > 0, bounds.height > 0 else { return }
        let visible = bounds.contains(sample.location)
        // While it's elsewhere, one "hidden" is enough.
        if !visible, lastCursor?.visible == false, pendingCursor == nil { return }
        func normalized(_ value: CGFloat) -> UInt16 { UInt16((min(max(value, 0), 1) * 65535).rounded()) }
        pendingCursor = CursorUpdate(
            x: normalized((sample.location.x - bounds.minX) / bounds.width),
            y: normalized((sample.location.y - bounds.minY) / bounds.height),
            visible: visible, shape: sample.shape
        )
        // At most once per display refresh, latest wins (mice report up to 1000 Hz).
        let interval = Duration.seconds(1 / max(frameRate, 1))
        if let last = lastCursorSent, MediaTime.now() - last < interval {
            guard !cursorFlushScheduled else { return }
            cursorFlushScheduled = true
            let wait = interval - (MediaTime.now() - last)
            DispatchQueue.main.asyncAfter(deadline: .now() + wait.inSeconds) { [weak self] in
                MainActor.assumeIsolated {
                    self?.cursorFlushScheduled = false
                    self?.flushCursor()
                }
            }
            return
        }
        flushCursor()
    }

    private func flushCursor() {
        guard let update = pendingCursor else { return }
        pendingCursor = nil
        lastCursor = update
        lastCursorSent = .now()
        cursorSinks.values.forEach { $0(update) }
    }

    public func inputEnded() {
        inputEndHandler?()
    }

    public func handleKey(_ key: KeyMessage) {
        guard session.activeDisplay != nil else { return }
        keyHandler?(key)
    }
}

final class SinkToken {}

// MARK: - Synthetic host

/// Generates an animated test pattern at a fixed rate — end-to-end streaming tests without a
/// virtual display or Screen Recording permission (`ginga serve --synthetic`, unit tests).
@MainActor
public final class SyntheticStreamHost: StreamHost {
    public let size: PixelSize
    /// The stream rate announced to receivers.
    public private(set) var frameRate: Double
    /// How fast frames are generated (the "display refresh"); defaults to the stream rate.
    public private(set) var generationRate: Double
    public private(set) var orientationRequests: [String] = []
    public private(set) var receivedInput: [InputMessage] = []
    public private(set) var inputEnds = 0
    public private(set) var receivedKeys: [KeyMessage] = []
    private let generator: SyntheticFrameGenerator
    private let sinks = OSAllocatedUnfairLock(uncheckedState: [ObjectIdentifier: @Sendable (SourceFrame) -> Void]())
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "dev.ginga.synthetic", qos: .userInteractive)
    private let last = OSAllocatedUnfairLock<SourceFrame?>(initialState: nil)
    public var onDisplayChange: (@MainActor (DisplayDescription) -> Void)?
    /// Tests: how long `prepareForStreaming` takes (the real host may create a display).
    public var prepareDelay: Duration = .zero
    private var leases: [StreamLease] = []
    private var isStill = false

    public init(size: PixelSize = PixelSize(width: 2560, height: 1600), frameRate: Double = 60, generationRate: Double? = nil) {
        self.size = size
        self.frameRate = frameRate
        self.generationRate = generationRate ?? frameRate
        self.generator = SyntheticFrameGenerator(size: size)
    }

    public private(set) var preparedFor: [ReceiverPanel?] = []

    public func prepareForStreaming(drawsCursor: Bool, receiver: ReceiverPanel?) async throws -> StreamLease {
        preparedFor.append(receiver)
        let lease = StreamLease(drawsCursor: drawsCursor) { [weak self] in self?.leasesChanged() }
        leases.append(lease)
        if prepareDelay > .zero { try? await Task.sleep(for: prepareDelay) }
        leasesChanged()
        return lease
    }

    /// Frames are generated while some lease is active (as capture runs on the real display).
    private func leasesChanged() {
        leases.removeAll { $0.isReleased }
        if !isStill, leases.contains(where: { $0.isActive }) { startGenerating() } else { stopGenerating() }
    }

    private func startGenerating() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: 1 / generationRate, leeway: .milliseconds(1))
        timer.setEventHandler(handler: Self.tick(generator: generator, sinks: sinks, last: last, size: size))
        timer.resume()
        self.timer = timer
    }

    /// Built outside the main actor: the handler runs on the timer queue, and a closure formed in
    /// a `@MainActor` method would be inferred main-actor-isolated (and trap at runtime).
    nonisolated private static func tick(
        generator: SyntheticFrameGenerator,
        sinks: OSAllocatedUnfairLock<[ObjectIdentifier: @Sendable (SourceFrame) -> Void]>,
        last: OSAllocatedUnfairLock<SourceFrame?>,
        size: PixelSize
    ) -> @Sendable () -> Void {
        {
            guard let buffer = generator.nextFrame() else { return }
            let frame = SourceFrame(pixelBuffer: buffer, captureTime: .now(), pixelSize: size)
            last.withLock { $0 = frame }
            let handlers = sinks.withLockUnchecked { Array($0.values) }
            handlers.forEach { $0(frame) }
        }
    }

    private func stopGenerating() {
        timer?.cancel()
        timer = nil
    }

    /// Tests: stops (or resumes) generation as if nothing changed on screen, whatever the leases want.
    public func setStill(_ still: Bool) {
        isStill = still
        leasesChanged()
    }

    /// Whether receivers currently want frames.
    public var isGenerating: Bool { timer != nil }
    /// Leases held and not released (tests).
    public var activeLeaseCount: Int { leases.filter { !$0.isReleased }.count }
    /// Pause states of the held leases (tests).
    public var leasePauseStates: [Bool] { leases.filter { !$0.isReleased }.map(\.isPaused) }

    public var latestFrame: SourceFrame? { last.withLock { $0 } }

    /// Simulates the display switching refresh rate (e.g. on a power-source change).
    public func changeRate(to rate: Double) async {
        frameRate = rate
        generationRate = rate
        if timer != nil {
            stopGenerating()
            startGenerating()
        }
        onDisplayChange?(displayDescription)
    }

    public var displayDescription: DisplayDescription {
        // The generation rate plays the display's refresh.
        DisplayDescription(id: 0, name: "Synthetic test pattern", looksLike: PixelDimensions(width: size.width / 2, height: size.height / 2),
                           hiDPI: true, refreshRate: generationRate, orientation: size.isPortrait ? "portrait" : "landscape")
    }

    public var expectedStreamSize: PixelSize { size }

    public func addFrameSink(_ sink: @escaping @Sendable (SourceFrame) -> Void) -> AnyObject {
        let token = SinkToken()
        sinks.withLockUnchecked { $0[ObjectIdentifier(token)] = sink }
        return token
    }

    public func removeFrameSink(_ token: AnyObject) {
        _ = sinks.withLockUnchecked { $0.removeValue(forKey: ObjectIdentifier(token)) }
    }

    public func requestOrientation(_ orientation: String) async {
        orientationRequests.append(orientation)
    }

    public func handleInput(_ input: InputMessage) {
        receivedInput.append(input)
    }

    public func inputEnded() {
        inputEnds += 1
    }

    public func handleKey(_ key: KeyMessage) {
        receivedKeys.append(key)
    }

    // MARK: Cursor (tests)

    public var supportsCursor = true
    private var cursorSinks: [ObjectIdentifier: @MainActor (CursorUpdate) -> Void] = [:]
    /// Whether held leases draw the pointer themselves (tests).
    public var leaseCursorStates: [Bool] { leases.filter { !$0.isReleased }.map(\.drawsCursor) }

    private var lastCursor: CursorUpdate?

    public func addCursorSink(_ sink: @escaping @MainActor (CursorUpdate) -> Void) -> AnyObject {
        let token = SinkToken()
        cursorSinks[ObjectIdentifier(token)] = sink
        if let lastCursor { sink(lastCursor) }  // like the display host: where the pointer is now
        return token
    }

    public func removeCursorSink(_ token: AnyObject) {
        cursorSinks.removeValue(forKey: ObjectIdentifier(token))
    }

    /// Tests: the pointer moved.
    public func moveCursor(_ update: CursorUpdate) {
        lastCursor = update
        cursorSinks.values.forEach { $0(update) }
    }
}

/// Moving NV12 test pattern (bars + a sweeping block) from a buffer pool; cheap enough for 120 fps.
public final class SyntheticFrameGenerator: @unchecked Sendable {  // `index` is guarded by `lock`; the pool is thread-safe
    private let size: PixelSize
    private let pool: CVPixelBufferPool?
    private let lock = NSLock()
    private var index = 0

    public init(size: PixelSize) {
        self.size = size
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: size.width,
            kCVPixelBufferHeightKey: size.height,
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey: 6] as CFDictionary, attributes as CFDictionary, &pool)
        self.pool = pool
    }

    public func nextFrame() -> CVPixelBuffer? {
        guard let pool else { return nil }
        var created: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created) == kCVReturnSuccess, let buffer = created else { return nil }
        let frame = lock.withLock { () -> Int in
            defer { index += 1 }
            return index
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = size.width, height = size.height
        let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let barWidth = max(width / 8, 1)
        let blockX = (frame * 16) % max(width - 256, 1)
        for y in 0..<height {
            let row = luma + y * lumaStride
            for bar in 0..<8 {
                memset(row + bar * barWidth, Int32(16 + bar * 28), min(barWidth, width - bar * barWidth))
            }
            if (height / 3..<height / 3 + 256).contains(y) {
                memset(row + blockX, 235, 256)
            }
        }
        let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!.assumingMemoryBound(to: UInt8.self)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        for y in 0..<height / 2 {
            memset(chroma + y * chromaStride, 128, width)
        }
        return buffer
    }
}
