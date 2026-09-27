import Foundation
import os
import GingaCore
import GingaProtocol
import GingaSecurity
import GingaSession
import Transport

/// Accepts receivers and keeps `adb reverse` alive. One receiver streams at a time; a new one
/// replaces it once the newcomer has itself completed the handshake (and pairing, on Wi‑Fi).
@MainActor
public final class StreamServer {
    public struct Status: Sendable {
        public var listeningPort: UInt16?
        public var adbAvailable: Bool
        public var adbDevices: [AdbDevice]
        public var connection: StreamConnection.Snapshot?
        public var lastError: String?
    }

    public private(set) var status: Status
    public var onChange: (@MainActor () -> Void)?
    /// Asks the Mac's user to confirm a Wi‑Fi pairing code. One request at a time.
    public var pairingPresenter: (@MainActor (PairingRequest) -> Void)?
    /// The pairing prompt showing, if any. A second request meanwhile is declined (its tablet can
    /// try again), so a device on the network can't pile prompts up.
    private var shownPairing: PairingRequest?
    /// Trust for connections from the loopback listener (adb reverse): physical by default;
    /// `requireLoopbackToken` makes them prove themselves.
    public var loopbackTrust: @Sendable (MessageConnection) -> PeerTrust = { _ in .physicalLink }
    /// Keys for the no-router mode (§6b); nil: not offered.
    public var directKeys: (any DirectKeyStore)?
    /// The token loopback connections must present, handed to tablets over adb.
    public private(set) var loopbackToken: String?

    private let host: any StreamHost
    private var settings: StreamingSettings
    private let adb: AdbBridge?
    private var server: TCPServer?
    /// The receiver that is streaming. A new connection never displaces it before it has itself
    /// authenticated and started streaming (anyone on the network can open a connection).
    private var current: StreamConnection? {
        didSet { updateActivity() }
    }
    /// Connections still saying HELLO, pairing or preparing; capped so they can't pile up.
    private var pending: [StreamConnection] = []
    /// Sessions that came through the loopback listener (adb reverse), which `stop()` ends.
    private var listenerSessions = Set<ObjectIdentifier>()
    static let maxPending = 4
    /// Held only while a receiver is streaming and not paused: keeps App Nap and timer
    /// coalescing from adding latency spikes, and the Mac from idle-sleeping under the person
    /// using the tablet.
    private var activity: NSObjectProtocol?
    /// Whether the streaming activity is held (tests).
    var holdsActivity: Bool { activity != nil }
    /// Battery ↔ AC changes switch the encoder's power hint (`StreamingSettings.encoderPower`),
    /// for receivers on every transport (so it lives as long as the server, not the TCP listener).
    private var powerMonitor: PowerSourceMonitor?

    public init(host: any StreamHost, settings: StreamingSettings, adb: AdbBridge? = AdbBridge.locate()) {
        self.host = host
        self.settings = settings
        self.adb = adb
        self.status = Status(listeningPort: nil, adbAvailable: adb != nil, adbDevices: [], connection: nil, lastError: nil)
        host.onDisplayChange = { [weak self] display in self?.displayChanged(display) }
        powerMonitor = PowerSourceMonitor { [weak self] onBattery in
            Log.streaming.info("power.source-changed on_battery=\(onBattery)")
            self?.current?.powerSourceChanged()
        }
    }

    public var isRunning: Bool { server != nil }
    /// Whether the receiver streaming now came over Wi‑Fi (e.g. the no-router mode).
    public var isStreamingOverWiFi: Bool { current.map { $0.isWiFi && $0.isStreaming } ?? false }

    /// Loopback connections must carry `token` in HELLO (PROTOCOL.md §5). It is handed to the
    /// Ginga app on every tablet over adb, after `adb reverse`. Call before `start`.
    public func requireLoopbackToken(_ token: String) {
        loopbackToken = token
        loopbackTrust = { _ in .adbLoopback(token: token) }
    }

    /// Every connection, streaming or not.
    private var sessions: [StreamConnection] { pending + (current.map { [$0] } ?? []) }

    /// Reaches connections that just started streaming too (they are promoted a moment later);
    /// each ignores it until WELCOME went out.
    private func displayChanged(_ display: DisplayDescription) {
        let frameRate = host.frameRate, latest = host.latestFrame
        for connection in sessions { connection.displayChanged(display, frameRate: frameRate, latest: latest) }
    }

    /// - Parameter port: overrides the configured port (0 = any free port, for tests).
    public func start(port: UInt16? = nil) throws {
        guard server == nil else { return }
        let server = try TCPServer(port: port ?? settings.port, loopbackOnly: true)
        server.start { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        self.server = server
        if settings.adbAutoReverse, let adb {
            let reversePort = port ?? settings.port
            adb.startMaintainingReverse(port: reversePort, token: loopbackToken) { [weak self] devices in
                Task { @MainActor in
                    self?.status.adbDevices = devices
                    self?.onChange?()
                }
            }
        }
    }

    /// Stops the loopback listener and `adb reverse`, and ends the sessions that came through
    /// them. Receivers on other transports (direct USB, Wi‑Fi) have their own switches.
    public func stop() {
        adb?.stop()
        closeSessions(reason: "shutdown") { listenerSessions.contains(ObjectIdentifier($0)) }
        server?.stop()
        server = nil
        status.listeningPort = nil
        onChange?()
    }

    /// The app is quitting: every receiver, on every transport, gets GOODBYE "shutdown" (so it
    /// knows to reconnect later instead of waiting for silence), then the listener stops.
    /// Returns whether all sessions closed within `timeout` (the run loop keeps turning meanwhile).
    @discardableResult
    public func shutdown(timeout: Duration = .milliseconds(300)) -> Bool {
        let closing = sessions
        closeSessions(reason: "shutdown") { _ in true }
        stop()
        // Wait for the GOODBYEs to go out (connections close off the main thread once flushed).
        let deadline = Date().addingTimeInterval(timeout.inSeconds)
        while !closing.allSatisfy(\.isClosed), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return closing.allSatisfy(\.isClosed)
    }

    /// Ends the sessions a predicate selects (e.g. a tablet whose pairing was revoked).
    public func closeSessions(reason: String, where matches: (StreamConnection) -> Bool) {
        for connection in sessions where matches(connection) {
            connection.close(reason: reason)
        }
    }

    /// Ends the Wi‑Fi sessions and waits (up to `timeout`) for their GOODBYEs to go out: the
    /// direct link does this before the Mac leaves the tablet's network.
    public func closeWiFiSessions(reason: String, timeout: Duration = .seconds(1)) async {
        let closing = sessions.filter(\.isWiFi)
        for connection in closing { connection.close(reason: reason) }
        let deadline = ContinuousClock.now + timeout
        while !closing.allSatisfy(\.isClosed), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Applies changed settings: the encoder power policy live, everything else to the next receiver.
    public func update(settings: StreamingSettings) {
        let previous = self.settings
        self.settings = settings
        if settings.encoderPower != previous.encoderPower { current?.setEncoderPower(settings.encoderPower) }
    }

    /// A receiver that connected over another transport: USB accessory (M6, physical) or Wi‑Fi
    /// (M7, TLS).
    /// - Parameter helloTimeout: `.some(nil)` waits for HELLO indefinitely (USB accessory links);
    ///   the default uses `StreamingSettings.helloTimeoutSeconds`.
    public func accept(_ connection: MessageConnection, trust: PeerTrust = .physicalLink, helloTimeout: Double?? = .none) {
        start(connection, trust: trust, helloTimeout: helloTimeout)
        onChange?()
    }

    /// Refreshes `status.connection` (poll from the UI's diagnostics timer).
    public func refresh() {
        status.connection = current?.snapshot
    }

    private func handle(_ event: TCPServer.Event) {
        switch event {
        case .listening(let port):
            status.listeningPort = port
            Log.streaming.info("server.ready port=\(port) adb=\(self.adb != nil)")
        case .failed(let reason):
            status.lastError = reason
            server?.stop()
            server = nil
        case .connection(let connection):
            let session = start(connection, trust: loopbackTrust(connection))
            listenerSessions.insert(ObjectIdentifier(session))
        }
        onChange?()
    }

    @discardableResult
    private func start(_ connection: MessageConnection, trust: PeerTrust, helloTimeout: Double?? = .none) -> StreamConnection {
        if pending.count >= Self.maxPending {
            pending.removeFirst().close(reason: "too many pending connections")
        }
        // Callbacks arrive on the main queue in order: streaming, then (maybe) closed.
        let stream = StreamConnection(
            connection: connection, host: host, settings: settings, trust: trust,
            pairingPresenter: { [weak self] request in self?.presentPairing(request) },
            helloTimeout: helloTimeout,
            onStateChange: { [weak self] changed in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.stateChanged(changed) } }
            },
            onUnauthorized: { [adb] in adb?.redeliverToken() },
            directKeys: directKeys,
            onClosed: { [weak self] closed in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.connectionClosed(closed) } }
            }
        )
        pending.append(stream)
        stream.start()
        return stream
    }

    private func presentPairing(_ request: PairingRequest) {
        guard let pairingPresenter else {
            request.respond(false)
            return
        }
        if let shown = shownPairing, !shown.isEnded {
            Log.streaming.info("stream.pairing-busy tablet=\(request.tabletName, privacy: .public)")
            request.respond(false)
            return
        }
        shownPairing = request
        pairingPresenter(request)
    }

    /// A pending connection started streaming: it becomes the receiver, replacing the previous one.
    private func stateChanged(_ connection: StreamConnection) {
        if connection.isStreaming, let index = pending.firstIndex(where: { $0 === connection }) {
            pending.remove(at: index)
            if let previous = current, previous !== connection { previous.close(reason: "replaced") }
            current = connection
        }
        updateActivity()
        onChange?()
    }

    private func connectionClosed(_ connection: StreamConnection) {
        listenerSessions.remove(ObjectIdentifier(connection))
        pending.removeAll { $0 === connection }
        guard current === connection else { return }
        current = nil
        status.connection = nil
        onChange?()
    }

    /// Held only while a receiver is actually showing the stream (not pending, not paused).
    private func updateActivity() {
        let streaming = current.map { !$0.isPaused } ?? false
        switch (streaming, activity) {
        case (true, nil):
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Streaming to a tablet")
        case (false, let token?):
            ProcessInfo.processInfo.endActivity(token)
            activity = nil
        default:
            break
        }
    }
}
