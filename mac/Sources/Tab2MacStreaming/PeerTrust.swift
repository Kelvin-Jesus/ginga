import Foundation
import Tab2MacSecurity

/// Why a receiver may see this Mac's screen and drive its input.
public enum PeerTrust: Sendable {
    /// USB (adb reverse, accessory) or loopback: the user connected the tablet physically and
    /// accepted the adb or accessory prompt.
    case physicalLink
    /// USB through `adb reverse`: a loopback connection like any local process could open, so
    /// HELLO must carry the token the Mac handed the tablet over adb (`LoopbackToken`).
    case adbLoopback(token: String)
    /// Wi‑Fi over TLS: the tablet's certificate must be pinned, or get pinned by pairing now.
    case tls(TLSPeer)
}

public struct TLSPeer: Sendable {
    /// This Mac's certificate fingerprint.
    public var local: CertificateFingerprint
    /// The tablet's certificate fingerprint from the TLS handshake (read when HELLO arrives,
    /// which is after the handshake).
    public var peer: @Sendable () -> CertificateFingerprint?
    public var pins: any PinStore
    /// Shown on the tablet while pairing.
    public var macName: String

    public init(local: CertificateFingerprint, peer: @escaping @Sendable () -> CertificateFingerprint?, pins: any PinStore, macName: String) {
        self.local = local
        self.peer = peer
        self.pins = pins
        self.macName = macName
    }
}

/// Asks the Mac's user whether the tablet shows the same code. The pairing can also end without
/// an answer (the tablet left or declined, or it timed out): `onEnd` handlers then close the prompt.
public final class PairingRequest: @unchecked Sendable {  // `ended` and `endHandlers` are guarded by `lock`
    public let tabletName: String
    public let code: String
    private let answer: @Sendable (Bool) -> Void
    private let lock = NSLock()
    private var ended = false
    private var endHandlers: [@MainActor @Sendable () -> Void] = []

    public init(tabletName: String, code: String, respond: @escaping @Sendable (Bool) -> Void) {
        self.tabletName = tabletName
        self.code = code
        self.answer = respond
    }

    /// The Mac user's answer. Only the first counts, and none once the pairing ended.
    public func respond(_ accepted: Bool) {
        guard finish() else { return }
        answer(accepted)
    }

    /// Whether the pairing is over, answered or not.
    public var isEnded: Bool { lock.withLock { ended } }

    /// Runs `handler` on the main actor if the pairing ends without an answer (right away if it
    /// already has).
    public func onEnd(_ handler: @escaping @MainActor @Sendable () -> Void) {
        let alreadyEnded = lock.withLock { () -> Bool in
            if !ended { endHandlers.append(handler) }
            return ended
        }
        if alreadyEnded { DispatchQueue.main.async { MainActor.assumeIsolated { handler() } } }
    }

    /// Ends the request without an answer (the connection's side).
    func end() {
        let handlers = lock.withLock { () -> [@MainActor @Sendable () -> Void] in
            guard !ended else { return [] }
            ended = true
            defer { endHandlers = [] }
            return endHandlers
        }
        guard !handlers.isEmpty else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { handlers.forEach { $0() } } }
    }

    private func finish() -> Bool {
        lock.withLock {
            guard !ended else { return false }
            ended = true
            endHandlers = []
            return true
        }
    }
}
