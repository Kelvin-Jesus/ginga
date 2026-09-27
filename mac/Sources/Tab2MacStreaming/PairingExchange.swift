import Foundation
import Tab2MacProtocol
import Tab2MacSecurity

/// The Mac's side of Wi‑Fi pairing (PROTOCOL.md §6) as a pure state machine: PAIRING messages and
/// the Mac user's answer go in, messages and decisions come out. No I/O, so every path is tested.
///
/// `required` → the tablet's `commit` → the Mac's `nonce` → the tablet's `reveal` (checked against
/// its commitment) → both users compare the code → the tablet's `confirmed` and the Mac user's
/// yes → `paired`. Anything out of order ends the attempt: the order is what keeps a man in the
/// middle from steering the code.
struct PairingExchange {
    enum Step: Equatable {
        case awaitingCommitment
        case awaitingReveal(commitment: Data)
        /// Both nonces are known: the users compare `code`.
        case comparing(code: String)
        case finished
    }

    enum Action: Equatable {
        case send(Pairing)
        /// Show `code` to the Mac's user and ask whether the tablet shows the same.
        case askMacUser(code: String)
        /// Both users confirmed: pin the tablet and continue the handshake.
        case pair
        /// The exchange broke the rules: send `rejected`, GOODBYE `error`, and close.
        case reject(reason: String)
        /// The Mac's user declined: send `rejected`, GOODBYE `user`, and close.
        case macUserDeclined
        /// The tablet declined: close.
        case tabletDeclined
    }

    let mac: CertificateFingerprint
    let tablet: CertificateFingerprint
    let macNonce: Data
    private(set) var step: Step = .awaitingCommitment
    private var macConfirmed = false
    private var tabletConfirmed = false

    init(mac: CertificateFingerprint, tablet: CertificateFingerprint, macNonce: Data = PairingCode.makeNonce()) {
        self.mac = mac
        self.tablet = tablet
        self.macNonce = macNonce
    }

    /// The opening message.
    func start(macName: String) -> Pairing {
        Pairing(state: .required, name: macName)
    }

    mutating func receive(_ message: Pairing) -> [Action] {
        switch (message.state, step) {
        case (_, .finished):
            return []
        case (.rejected, _):
            step = .finished
            return [.tabletDeclined]
        case (.commit, .awaitingCommitment):
            guard let commitment = message.commitment.flatMap(Hex.decode), commitment.count == 32 else {
                return fail("malformed commitment")
            }
            step = .awaitingReveal(commitment: commitment)
            return [.send(Pairing(state: .nonce, nonce: Hex.encode(macNonce)))]
        case (.reveal, .awaitingReveal(let commitment)):
            guard let nonce = message.nonce.flatMap(Hex.decode), nonce.count == PairingCode.nonceLength else {
                return fail("malformed nonce")
            }
            guard PairingCode.commitment(tablet: tablet, mac: mac, tabletNonce: nonce) == commitment else {
                return fail("the tablet's nonce doesn't match its commitment")
            }
            let code = PairingCode.code(mac: mac, tablet: tablet, macNonce: macNonce, tabletNonce: nonce)
            step = .comparing(code: code)
            return [.askMacUser(code: code)]
        case (.confirmed, .comparing):
            tabletConfirmed = true
            return completeIfBothConfirmed()
        case (.confirmed, _):
            // An app from before commitments confirms a code computed without nonces.
            return fail("the tablet confirmed before the codes could be compared (update Ginga on the tablet)")
        case (.commit, _), (.reveal, _):
            return fail("unexpected \(message.state) during pairing")
        default:
            return []  // Mac → tablet states, or ones this Mac doesn't know
        }
    }

    mutating func macUserAnswered(_ accepted: Bool) -> [Action] {
        guard case .comparing = step else { return [] }
        guard accepted else {
            step = .finished
            return [.macUserDeclined]
        }
        macConfirmed = true
        return completeIfBothConfirmed()
    }

    private mutating func completeIfBothConfirmed() -> [Action] {
        guard macConfirmed, tabletConfirmed else { return [] }
        step = .finished
        return [.pair]
    }

    private mutating func fail(_ reason: String) -> [Action] {
        step = .finished
        return [.reject(reason: reason)]
    }
}
