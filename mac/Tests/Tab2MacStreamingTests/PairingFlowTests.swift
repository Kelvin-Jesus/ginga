import Foundation
import Tab2MacCore
import Tab2MacProtocol
import Tab2MacSecurity
import Tab2MacSession
import Testing
import Transport
import VideoPipeline
@testable import Tab2MacStreaming

/// Wi‑Fi pairing by numeric comparison over the real protocol (TLS itself is replaced by the
/// trust policy: the fingerprints stand for the two certificates).
@MainActor
@Suite("Wi-Fi pairing", .serialized, .enabled(if: VideoToolboxEncoder.isHardwareEncoderAvailable(.hevc)))
struct PairingFlowTests {
    let host = SyntheticStreamHost(size: PixelSize(width: 640, height: 400), frameRate: 60)
    let mac = CertificateFingerprint(certificate: Data("mac".utf8))
    let tablet = CertificateFingerprint(certificate: Data("tablet".utf8))
    let pins = MemoryPinStore()
    let requests = Requests()

    final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [PairingRequest] = []
        func append(_ request: PairingRequest) { lock.withLock { items.append(request) } }
        var all: [PairingRequest] { lock.withLock { items } }
    }

    private func startServer() async throws -> (StreamServer, UInt16) {
        let server = StreamServer(host: host, settings: StreamingSettings(bitrateKbps: 4000, port: 0, adbAutoReverse: false), adb: nil)
        let tablet = tablet
        let peer = TLSPeer(local: mac, peer: { tablet }, pins: pins, macName: "Test Mac")
        server.loopbackTrust = { _ in .tls(peer) }
        let requests = requests
        server.pairingPresenter = { requests.append($0) }
        try server.start(port: 0)
        #expect(await eventually { server.status.listeningPort != nil })
        return (server, try #require(server.status.listeningPort))
    }

    private func pairingStates(_ receiver: TestReceiver) -> [Pairing.State] {
        receiver.received.compactMap { if case .pairing(let pairing) = $0 { pairing.state } else { nil } }
    }

    /// The tablet's half of the exchange up to the code: commit to a nonce, learn the Mac's, reveal.
    /// Returns the code the tablet shows.
    private func commitAndReveal(_ receiver: TestReceiver, nonce: Data = PairingCode.makeNonce()) async throws -> String {
        #expect(await eventually { pairingStates(receiver) == [.required] })
        let commitment = PairingCode.commitment(tablet: tablet, mac: mac, tabletNonce: nonce)
        receiver.connection.send(.pairing(Pairing(state: .commit, commitment: Hex.encode(commitment))))
        #expect(await eventually { pairingStates(receiver) == [.required, .nonce] })
        let macNonce = try #require(receiver.received.lazy.compactMap { message -> Data? in
            guard case .pairing(let pairing) = message, pairing.state == .nonce else { return nil }
            return pairing.nonce.flatMap(Hex.decode)
        }.first)
        receiver.connection.send(.pairing(Pairing(state: .reveal, nonce: Hex.encode(nonce))))
        return PairingCode.code(mac: mac, tablet: tablet, macNonce: macNonce, tabletNonce: nonce)
    }

    @Test func anUnknownTabletPairsWhenBothSidesConfirm() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(features: ["clock-sync", "pairing"])

        let code = try await commitAndReveal(receiver)
        #expect(await eventually { requests.all.count == 1 })
        let request = try #require(requests.all.first)
        #expect(request.code == code)  // both screens show the same digits
        #expect(request.tabletName == "samsung SM-X730")
        #expect(receiver.videoFrames.isEmpty)  // nothing streams before pairing

        receiver.connection.send(.pairing(Pairing(state: .confirmed)))
        request.respond(true)
        #expect(await eventually { pairingStates(receiver) == [.required, .nonce, .paired] })
        #expect(await eventually { receiver.videoFrames.count >= 3 })
        #expect(pins.tablet(for: tablet)?.name == "samsung SM-X730")
    }

    @Test func aRejectionOnTheMacEndsTheSessionWithoutAPin() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(features: ["pairing"])
        _ = try await commitAndReveal(receiver)
        #expect(await eventually { requests.all.count == 1 })
        receiver.connection.send(.pairing(Pairing(state: .confirmed)))
        try #require(requests.all.first).respond(false)
        #expect(await eventually { pairingStates(receiver) == [.required, .nonce, .rejected] })
        #expect(await eventually { receiver.closed })
        #expect(receiver.first { if case .goodbye(let goodbye) = $0 { goodbye } else { nil } }?.reason == "user")
        #expect(pins.all.isEmpty)
        #expect(receiver.videoFrames.isEmpty)
    }

    /// A tablet app from before commitments confirms a code computed without nonces: refused,
    /// and the Mac never shows a prompt for it.
    @Test func confirmingWithoutTheCommitmentStepsIsRefused() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(features: ["pairing"])
        #expect(await eventually { pairingStates(receiver) == [.required] })
        receiver.connection.send(.pairing(Pairing(state: .confirmed)))
        #expect(await eventually { pairingStates(receiver) == [.required, .rejected] && receiver.closed })
        #expect(requests.all.isEmpty)
        #expect(pins.all.isEmpty)
    }

    /// One prompt at a time: a device on the network can't pile prompts up on the Mac.
    @Test func aSecondPairingWhileOneIsShownIsDeclined() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let first = TestReceiver(port: port)
        first.sendHello(features: ["pairing"])
        _ = try await commitAndReveal(first)
        #expect(await eventually { requests.all.count == 1 })

        let second = TestReceiver(port: port)
        second.sendHello(features: ["pairing"])
        _ = try await commitAndReveal(second)
        #expect(await eventually { second.closed })
        #expect(pairingStates(second).last == .rejected)
        #expect(requests.all.count == 1)
        #expect(!first.closed)  // the prompt showing is unaffected
    }

    /// The tablet went away while the Mac's prompt was up: the prompt is withdrawn, and a late
    /// answer changes nothing.
    @Test func thePromptIsWithdrawnWhenTheTabletLeaves() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(features: ["pairing"])
        _ = try await commitAndReveal(receiver)
        #expect(await eventually { requests.all.count == 1 })
        let request = try #require(requests.all.first)
        let withdrawn = Counter()
        request.onEnd { withdrawn.increment() }
        receiver.connection.close(reason: "left")
        #expect(await eventually { withdrawn.value == 1 })
        #expect(request.isEnded)
        request.respond(true)
        try await Task.sleep(for: .milliseconds(50))
        #expect(pins.all.isEmpty)
    }

    @Test func aPairedTabletStreamsRightAway() async throws {
        try pins.add(PairedTablet(fingerprint: tablet, name: "Tab S11"))
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(features: ["pairing"])
        #expect(await eventually { receiver.videoFrames.count >= 3 })
        #expect(pairingStates(receiver).isEmpty)
        #expect(requests.all.isEmpty)
    }

    /// Forgetting a tablet ends its session at once; it has to pair again to come back.
    @Test func forgettingATabletEndsItsSession() async throws {
        try pins.add(PairedTablet(fingerprint: tablet, name: "Tab S11"))
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(features: ["pairing"])
        #expect(await eventually { receiver.videoFrames.count >= 3 })
        let wifi = WiFiService(server: server, pins: pins)
        wifi.forget(try #require(wifi.pairedTablets.first))
        #expect(await eventually { receiver.closed })
        #expect(receiver.first { if case .goodbye(let goodbye) = $0 { goodbye } else { nil } }?.reason == "user")
        #expect(pins.tablet(for: tablet) == nil)

        let again = TestReceiver(port: port)
        again.sendHello(features: ["pairing"])
        #expect(await eventually { pairingStates(again) == [.required] })
    }

    /// Turning Wi‑Fi off ends Wi‑Fi sessions, not just the listener.
    @Test func stoppingWiFiEndsItsSessions() async throws {
        try pins.add(PairedTablet(fingerprint: tablet, name: "Tab S11"))
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(features: ["pairing"])
        #expect(await eventually { receiver.videoFrames.count >= 3 })
        WiFiService(server: server, pins: pins).stop()
        #expect(await eventually { receiver.closed })
        #expect(pins.tablet(for: tablet) != nil)  // still paired
    }

    /// The tablet forgot this Mac (or the Mac's identity changed) while the Mac still pins the
    /// tablet: the tablet asks to pair, and gets the full exchange instead of a WELCOME it would
    /// have to refuse.
    @Test func aTabletThatForgotTheMacCanAskToPairAgain() async throws {
        try pins.add(PairedTablet(fingerprint: tablet, name: "Tab S11"))
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(features: ["pairing"], pairingRequested: true)
        let code = try await commitAndReveal(receiver)
        #expect(await eventually { requests.all.count == 1 })
        #expect(requests.all.first?.code == code)
        #expect(receiver.first { if case .welcome(let welcome) = $0 { welcome } else { nil } } == nil)
        receiver.connection.send(.pairing(Pairing(state: .confirmed)))
        try #require(requests.all.first).respond(true)
        #expect(await eventually { receiver.videoFrames.count >= 3 })
    }

    @Test func aTabletThatCannotPairIsRefusedOnWiFi() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(features: ["clock-sync"])
        #expect(await eventually { receiver.closed })
        let error = try #require(receiver.first { if case .error(let error) = $0 { error } else { nil } })
        #expect(error.code == "unsupported")
        #expect(receiver.videoFrames.isEmpty)
    }

    @Test func inputBeforeTheSessionIsAuthenticatedIsIgnored() async throws {
        let (server, port) = try await startServer()
        defer { server.stop() }
        let receiver = TestReceiver(port: port)
        receiver.sendHello(features: ["pairing"])
        #expect(await eventually { pairingStates(receiver) == [.required] })
        receiver.connection.send(.input(InputMessage(
            sequence: 1, eventTimeUs: 1, kind: .touch, action: .down,
            pointers: [PointerRecord(pointerId: 0, toolType: .finger, buttons: [], x: 100, y: 100, pressure: 30000, tiltX: 0, tiltY: 0)]
        )))
        try await Task.sleep(for: .milliseconds(100))
        #expect(host.receivedInput.isEmpty)
    }
}
