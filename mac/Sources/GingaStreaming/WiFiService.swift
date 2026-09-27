import Foundation
import os
import Security
import GingaCore
import GingaSecurity
import Transport

/// Accepts tablets over Wi‑Fi (M7): TLS with this Mac's identity, Bonjour `_ginga._tcp`, and
/// every connection handed to the stream server as `.tls` so the session enforces pairing.
@MainActor
public final class WiFiService {
    public private(set) var isRunning = false
    public private(set) var port: UInt16?
    public private(set) var lastError: String?
    public var onChange: (@MainActor () -> Void)?

    private let server: StreamServer
    private let pins: any PinStore
    private var listener: TLSListener?

    public init(server: StreamServer, pins: any PinStore = KeychainPinStore()) {
        self.server = server
        self.pins = pins
    }

    public var pairedTablets: [PairedTablet] { pins.all.sorted { $0.pairedAt < $1.pairedAt } }

    /// Removes the tablet's pin and ends its session: it has to pair again to connect.
    public func forget(_ tablet: PairedTablet) {
        try? pins.remove(tablet.fingerprint)
        server.closeSessions(reason: "user") { $0.peerFingerprint == tablet.fingerprint }
        onChange?()
    }

    /// Creates this Mac's TLS identity on first use (login keychain) and starts advertising.
    public func start(macName: String, port: UInt16 = 0) {
        guard listener == nil else { return }
        do {
            let identity = try TLSIdentityStore.loadOrCreate(commonName: "Ginga on \(macName)")
            let txt = ["pv": "1", "id": String(identity.fingerprint.hex.prefix(12)), "name": macName]
            let listener = try TLSListener(
                identity: identity.identity, port: port,
                advertisement: TLSListener.Advertisement(name: macName, txt: txt)
            )
            let local = identity.fingerprint
            let pins = pins
            listener.start { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    switch event {
                    case .ready(let port):
                        self.port = port
                        self.isRunning = true
                        Log.streaming.info("wifi.ready port=\(port)")
                    case .failed(let reason):
                        self.lastError = reason
                        self.isRunning = false
                        Log.streaming.error("wifi.failed reason=\(reason, privacy: .public)")
                    case .connection(let connection, let transport):
                        let peer = TLSPeer(
                            local: local,
                            peer: { transport.peerCertificate().map(CertificateFingerprint.init(certificate:)) },
                            pins: pins, macName: macName
                        )
                        self.server.accept(connection, trust: .tls(peer))
                    }
                    self.onChange?()
                }
            }
            self.listener = listener
        } catch {
            lastError = String(describing: error)
            Log.streaming.error("wifi.start-failed reason=\(String(describing: error), privacy: .public)")
        }
        onChange?()
    }

    /// Stops advertising and accepting, and ends the Wi‑Fi sessions (a stopped listener leaves
    /// its accepted connections open).
    /// Starts if needed and waits (briefly) for the listening port: the no-router mode tells the
    /// tablet where to connect.
    public func ensureRunning(macName: String) async -> UInt16? {
        if listener == nil { start(macName: macName) }
        for _ in 0..<50 where port == nil && lastError == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return port
    }

    public func stop() {
        listener?.stop()
        listener = nil
        server.closeSessions(reason: "user") { $0.isWiFi }
        isRunning = false
        port = nil
        onChange?()
    }
}
