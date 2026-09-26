import Foundation
import Tab2MacProtocol
import Tab2MacSecurity
import Testing
@testable import Tab2MacStreaming

@Suite("PairingExchange")
struct PairingExchangeTests {
    let mac = CertificateFingerprint(certificate: Data("mac".utf8))
    let tablet = CertificateFingerprint(certificate: Data("tablet".utf8))
    let macNonce = Data(repeating: 0x33, count: 32)
    let tabletNonce = Data(repeating: 0x44, count: 32)

    func exchange() -> PairingExchange {
        PairingExchange(mac: mac, tablet: tablet, macNonce: macNonce)
    }

    var commit: Pairing {
        Pairing(state: .commit, commitment: Hex.encode(PairingCode.commitment(tablet: tablet, mac: mac, tabletNonce: tabletNonce)))
    }

    var reveal: Pairing { Pairing(state: .reveal, nonce: Hex.encode(tabletNonce)) }

    var code: String { PairingCode.code(mac: mac, tablet: tablet, macNonce: macNonce, tabletNonce: tabletNonce) }

    @Test func theFullExchangePairsWhenBothUsersConfirm() {
        var exchange = exchange()
        #expect(exchange.start(macName: "Mac") == Pairing(state: .required, name: "Mac"))
        #expect(exchange.receive(commit) == [.send(Pairing(state: .nonce, nonce: Hex.encode(macNonce)))])
        #expect(exchange.receive(reveal) == [.askMacUser(code: code)])
        #expect(exchange.receive(Pairing(state: .confirmed)).isEmpty)  // the Mac's user hasn't answered yet
        #expect(exchange.macUserAnswered(true) == [.pair])
        #expect(exchange.step == .finished)
    }

    @Test func eitherUserMayConfirmFirst() {
        var exchange = exchange()
        _ = exchange.receive(commit)
        _ = exchange.receive(reveal)
        #expect(exchange.macUserAnswered(true).isEmpty)
        #expect(exchange.receive(Pairing(state: .confirmed)) == [.pair])
    }

    /// A nonce chosen after seeing the Mac's (what a man in the middle would need) is refused.
    @Test func aRevealThatDoesNotMatchTheCommitmentIsRejected() {
        var exchange = exchange()
        _ = exchange.receive(commit)
        let actions = exchange.receive(Pairing(state: .reveal, nonce: Hex.encode(Data(repeating: 0x45, count: 32))))
        #expect(actions == [.reject(reason: "the tablet's nonce doesn't match its commitment")])
        #expect(exchange.step == .finished)
    }

    /// Steps may not be skipped or reordered: the order is what protects the code.
    @Test func outOfOrderMessagesEndTheAttempt() {
        var early = exchange()
        #expect(early.receive(reveal).first.map(isReject) == true)  // reveal before commit
        var confirmedEarly = exchange()
        _ = confirmedEarly.receive(commit)
        #expect(confirmedEarly.receive(Pairing(state: .confirmed)).first.map(isReject) == true)
        var twice = exchange()
        _ = twice.receive(commit)
        #expect(twice.receive(commit).first.map(isReject) == true)
        var answeredEarly = exchange()
        #expect(answeredEarly.macUserAnswered(true).isEmpty)  // nothing to confirm yet
    }

    @Test func malformedValuesAreRejected() {
        var shortCommitment = exchange()
        #expect(shortCommitment.receive(Pairing(state: .commit, commitment: "abcd")).first.map(isReject) == true)
        var missingNonce = exchange()
        _ = missingNonce.receive(commit)
        #expect(missingNonce.receive(Pairing(state: .reveal)).first.map(isReject) == true)
    }

    @Test func declinesEndIt() {
        var tabletDeclines = exchange()
        _ = tabletDeclines.receive(commit)
        #expect(tabletDeclines.receive(Pairing(state: .rejected)) == [.tabletDeclined])
        var macDeclines = exchange()
        _ = macDeclines.receive(commit)
        _ = macDeclines.receive(reveal)
        #expect(macDeclines.macUserAnswered(false) == [.macUserDeclined])
        #expect(macDeclines.receive(Pairing(state: .confirmed)).isEmpty)  // over
    }

    @Test func unknownStatesAreIgnored() throws {
        var exchange = exchange()
        let future = try JSONDecoder().decode(Pairing.self, from: Data(#"{"state":"some-future-step"}"#.utf8))
        #expect(future.state.rawValue == "some-future-step")
        #expect(exchange.receive(future).isEmpty)
        #expect(exchange.step == .awaitingCommitment)
    }

    private func isReject(_ action: PairingExchange.Action) -> Bool {
        if case .reject = action { return true }
        return false
    }
}
