import Foundation
import os
import Tab2MacCore
import Tab2MacSecurity

extension Log {
    public static let directLink = Logger(subsystem: subsystem, category: "direct-link")
}

/// What the tablet hands over (PROTOCOL.md §6b): its network, for this session only.
public struct DirectCredentials: Codable, Equatable, Sendable {
    public var ssid: String
    public var psk: String
    public var session: String
    /// Unix seconds.
    public var expires: Int

    public init(ssid: String, psk: String, session: String, expires: Int) {
        self.ssid = ssid
        self.psk = psk
        self.session = session
        self.expires = expires
    }
}

/// Where the tablet finds the Mac on its network.
public struct DirectAddress: Codable, Equatable, Sendable {
    public var host: String
    public var port: Int
    public var session: String
}

/// The Bluetooth LE side: find a tablet offering a network, read its sealed credentials, write
/// back the sealed address.
public protocol DirectCredentialChannel: AnyObject, Sendable {
    func readCredentials(timeout: Duration) async throws -> Data
    func writeAddress(_ value: Data) async throws
    func close()
}

/// The Mac's Wi‑Fi: which network it's on, joining the tablet's, and going back.
public protocol DirectWiFi: AnyObject, Sendable {
    /// Asks for what reading and joining networks needs (Location on macOS). False if refused.
    func authorize() async -> Bool
    var currentNetwork: String? { get }
    func join(ssid: String, password: String, timeout: Duration) async throws
    /// The Mac's IPv4 address on the Wi‑Fi interface, once it has one.
    func address(timeout: Duration) async -> String?
    /// Leaves the tablet's network (`leaving`) and gets back to `previous`, or to whatever known
    /// network macOS picks. Never drops a network the Mac is already on other than `leaving`.
    func restore(previous: String?, leaving: String) async -> RestoreOutcome
}

/// No router (PROTOCOL.md §6b): the Mac joins the network the tablet creates, and the usual
/// Wi‑Fi session (TLS, pinning) runs on it. Only ever started by the user, because the Mac leaves
/// its current Wi‑Fi network (and, without Ethernet, the internet) until it ends.
@MainActor
public final class DirectLinkSession {
    public enum State: Equatable, Sendable {
        case idle
        case authorizing
        case searching
        case joining(ssid: String)
        case waitingForTablet
        case connected
        case restoring
        case failed(String)
    }

    public struct Timing: Sendable {
        public var search: Duration = .seconds(30)
        public var join: Duration = .seconds(30)
        public var address: Duration = .seconds(15)
        public var tabletArrival: Duration = .seconds(30)
        /// A dropped session gets this long to come back before the Mac goes home.
        public var reconnectGrace: Duration = .seconds(10)
        public init() {}
    }

    public private(set) var state: State = .idle {
        didSet { if state != oldValue { onChange?(state) } }
    }
    public var onChange: (@MainActor (State) -> Void)?
    public var isActive: Bool {
        switch state {
        case .idle, .failed: false
        default: true
        }
    }

    private let keys: any DirectKeyStore
    private let channel: any DirectCredentialChannel
    private let wifi: any DirectWiFi
    private let listenerPort: @MainActor () async -> UInt16?
    private let closeSessions: @MainActor () async -> Void
    private let timing: Timing
    private let now: @Sendable () -> Date
    private var previousNetwork: String?
    private var tabletNetwork: String?
    private var joined = false
    private var waiter: Task<Void, Never>?

    public init(
        keys: any DirectKeyStore, channel: any DirectCredentialChannel, wifi: any DirectWiFi,
        listenerPort: @escaping @MainActor () async -> UInt16?, closeSessions: @escaping @MainActor () async -> Void = {},
        timing: Timing = Timing(), now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.keys = keys
        self.channel = channel
        self.wifi = wifi
        self.listenerPort = listenerPort
        self.closeSessions = closeSessions
        self.timing = timing
        self.now = now
    }

    /// The user clicked "Connect directly to the tablet".
    public func start() async {
        guard !isActive else { return }
        do {
            state = .authorizing
            guard await wifi.authorize() else { throw Failure("Tab2Mac needs Location access to see and join Wi‑Fi networks (System Settings › Privacy & Security › Location Services)") }

            state = .searching
            let sealed = try await channel.readCredentials(timeout: timing.search)
            guard let keyId = DirectLinkCrypto.keyId(of: sealed), let key = keys.key(forId: keyId) else {
                throw Failure("this tablet has no direct-link key yet: connect it once by USB or Wi‑Fi")
            }
            let credentials: DirectCredentials
            do {
                credentials = try JSONDecoder().decode(DirectCredentials.self, from: try DirectLinkCrypto.open(sealed, key: key.key, purpose: .credentials))
            } catch {
                throw Failure("the tablet's credentials didn't check out")
            }
            guard credentials.expires > Int(now().timeIntervalSince1970) else { throw Failure("the tablet's credentials have expired; start again on the tablet") }

            previousNetwork = wifi.currentNetwork
            tabletNetwork = credentials.ssid
            state = .joining(ssid: credentials.ssid)
            joined = true  // from here on, any failure goes back to the previous network
            try await wifi.join(ssid: credentials.ssid, password: credentials.psk, timeout: timing.join)
            guard let host = await wifi.address(timeout: timing.address) else { throw Failure("no address on the tablet's network") }
            guard let port = await listenerPort() else { throw Failure("the Wi‑Fi listener isn't running") }

            let address = DirectAddress(host: host, port: Int(port), session: credentials.session)
            try await channel.writeAddress(DirectLinkCrypto.seal(try JSONEncoder().encode(address), key: key.key, keyId: key.keyId, purpose: .address))
            channel.close()
            Log.directLink.info("direct.joined ssid_length=\(credentials.ssid.count) host=\(host, privacy: .public) port=\(port)")
            state = .waitingForTablet
            waitThenGoHome(after: timing.tabletArrival, reason: "the tablet didn't connect")
        } catch {
            channel.close()
            let message = (error as? Failure)?.message ?? String(describing: error)
            Log.directLink.error("direct.failed reason=\(message, privacy: .public)")
            await goHome(reason: "failed")
            state = .failed(message)
        }
    }

    /// A Wi‑Fi session from the tablet started streaming.
    public func tabletConnected() {
        guard state == .waitingForTablet || state == .connected else { return }
        waiter?.cancel()
        waiter = nil
        state = .connected
    }

    /// The session ended: give it a moment to come back, then return to the previous network.
    public func tabletDisconnected() {
        guard state == .connected else { return }
        state = .waitingForTablet
        waitThenGoHome(after: timing.reconnectGrace, reason: "the tablet left")
    }

    /// The user ended it, or the app quits.
    public func end() async {
        guard isActive else { return }
        waiter?.cancel()
        waiter = nil
        channel.close()
        await goHome(reason: "ended")
        state = .idle
    }

    private func waitThenGoHome(after delay: Duration, reason: String) {
        waiter?.cancel()
        waiter = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.state == .waitingForTablet else { return }
            await self.goHome(reason: reason)
            self.state = .idle
        }
    }

    private func goHome(reason: String) async {
        guard joined, let tabletNetwork else { return }
        joined = false
        state = .restoring
        Log.directLink.info("direct.ending reason=\(reason, privacy: .public)")
        let started = ContinuousClock.now
        // GOODBYE first: the tablet takes its network down with the session, so macOS can't
        // auto-join back onto it, and the tablet doesn't wait 5 s of silence to notice.
        await closeSessions()
        let outcome = await wifi.restore(previous: previousNetwork, leaving: tabletNetwork)
        Log.directLink.info("direct.restored outcome=\(outcome.rawValue, privacy: .public) had_previous=\(self.previousNetwork != nil) seconds=\((ContinuousClock.now - started).inSeconds)")
    }

    struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
