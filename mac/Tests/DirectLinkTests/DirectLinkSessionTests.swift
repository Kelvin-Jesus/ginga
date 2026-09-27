import Foundation
import GingaSecurity
import Testing
@testable import DirectLink

final class FakeChannel: DirectCredentialChannel, @unchecked Sendable {
    var credentials: Data?
    var readError: (any Error)?
    private(set) var written: Data?
    private(set) var closed = 0
    func readCredentials(timeout: Duration) async throws -> Data {
        if let readError { throw readError }
        return credentials ?? Data()
    }
    func writeAddress(_ value: Data) async throws { written = value }
    func close() { closed += 1 }
}

final class FakeWiFi: DirectWiFi, @unchecked Sendable {
    var authorized = true
    var network: String? = "Home"
    var joinError: (any Error)?
    var address: String? = "192.168.49.23"
    private(set) var joins: [(ssid: String, password: String)] = []
    private(set) var restoredTo: [String?] = []
    private(set) var left: [String] = []
    func authorize() async -> Bool { authorized }
    var currentNetwork: String? { network }
    func join(ssid: String, password: String, timeout: Duration) async throws {
        if let joinError { throw joinError }
        joins.append((ssid, password))
        network = ssid
    }
    func address(timeout: Duration) async -> String? { address }
    func restore(previous: String?, leaving: String) async -> RestoreOutcome {
        restoredTo.append(previous)
        left.append(leaving)
        network = previous
        return previous == nil ? .none : .previous
    }
}

struct Boom: Error {}

@MainActor
@Suite("DirectLinkSession")
struct DirectLinkSessionTests {
    let key = DirectKey(keyId: Data([1, 2, 3, 4, 5, 6, 7, 8]), key: Data(repeating: 0x55, count: 32), deviceId: "tab", name: "Tab S11")
    let channel = FakeChannel()
    let wifi = FakeWiFi()
    let clock = Date(timeIntervalSince1970: 1_700_000_000)

    func sealedCredentials(expires: Int = 1_700_000_300, key: DirectKey? = nil) throws -> Data {
        let credentials = DirectCredentials(ssid: "DIRECT-T2-0102", psk: "per-session-secret", session: "abc", expires: expires)
        let key = key ?? self.key
        return try DirectLinkCrypto.seal(try JSONEncoder().encode(credentials), key: key.key, keyId: key.keyId, purpose: .credentials)
    }

    func session(timing: DirectLinkSession.Timing = DirectLinkSession.Timing(), closeSessions: @escaping @MainActor () async -> Void = {}) -> DirectLinkSession {
        let clock = clock
        return DirectLinkSession(
            keys: MemoryDirectKeyStore([key]), channel: channel, wifi: wifi, listenerPort: { 55471 }, closeSessions: closeSessions, timing: timing, now: { clock }
        )
    }

    @Test func joinsTheTabletsNetworkAndTellsItWhereTheMacIs() async throws {
        channel.credentials = try sealedCredentials()
        let session = session()
        await session.start()
        #expect(session.state == .waitingForTablet)
        #expect(wifi.joins.map(\.ssid) == ["DIRECT-T2-0102"] && wifi.joins.first?.password == "per-session-secret")
        let written = try #require(channel.written)
        let address = try JSONDecoder().decode(DirectAddress.self, from: try DirectLinkCrypto.open(written, key: key.key, purpose: .address))
        #expect(address == DirectAddress(host: "192.168.49.23", port: 55471, session: "abc"))
        session.tabletConnected()
        #expect(session.state == .connected)
        await session.end()
        #expect(session.state == .idle)
        #expect(wifi.restoredTo == ["Home"])  // back to where the Mac was
        #expect(wifi.left == ["DIRECT-T2-0102"])
    }

    /// The tablet hears GOODBYE (and takes its network down) before the Mac leaves the network.
    @Test func endingClosesTheSessionsBeforeLeaving() async throws {
        channel.credentials = try sealedCredentials()
        var events: [String] = []
        let wifi = wifi
        let session = session(closeSessions: { events.append("closed with restores=\(wifi.restoredTo.count)") })
        await session.start()
        session.tabletConnected()
        await session.end()
        #expect(events == ["closed with restores=0"])
        #expect(wifi.restoredTo == ["Home"])
    }

    @Test func failuresAfterJoiningGoBackToThePreviousNetwork() async throws {
        channel.credentials = try sealedCredentials()
        wifi.address = nil  // e.g. DHCP never answers
        let session = session()
        await session.start()
        guard case .failed = session.state else { Issue.record("expected failure, got \(session.state)"); return }
        #expect(wifi.restoredTo == ["Home"])
    }

    @Test func failuresBeforeJoiningLeaveTheNetworkAlone() async throws {
        let session = session()
        channel.readError = Boom()
        await session.start()
        guard case .failed = session.state else { Issue.record("expected failure"); return }
        #expect(wifi.joins.isEmpty && wifi.restoredTo.isEmpty)

        channel.readError = nil
        channel.credentials = try sealedCredentials(expires: 1_699_999_999)  // expired
        await session.start()
        guard case .failed(let reason) = session.state else { Issue.record("expected failure"); return }
        #expect(reason.contains("expired"))
        #expect(wifi.joins.isEmpty && wifi.restoredTo.isEmpty)

        let stranger = DirectKey(keyId: Data(repeating: 9, count: 8), key: Data(repeating: 1, count: 32), deviceId: "x", name: "x")
        channel.credentials = try sealedCredentials(key: stranger)
        await session.start()
        guard case .failed(let unknown) = session.state else { Issue.record("expected failure"); return }
        #expect(unknown.contains("no direct-link key"))

        wifi.authorized = false
        await session.start()
        guard case .failed(let location) = session.state else { Issue.record("expected failure"); return }
        #expect(location.contains("Location"))
        #expect(wifi.joins.isEmpty)
    }

    @Test func aJoinFailureStillRestores() async throws {
        channel.credentials = try sealedCredentials()
        wifi.joinError = Boom()
        let session = session()
        await session.start()
        guard case .failed = session.state else { Issue.record("expected failure"); return }
        #expect(wifi.restoredTo == ["Home"])
        #expect(channel.closed >= 1)
    }

    @Test func aTabletThatNeverComesOrLeavesSendsTheMacHome() async throws {
        var timing = DirectLinkSession.Timing()
        timing.tabletArrival = .milliseconds(50)
        timing.reconnectGrace = .milliseconds(50)
        channel.credentials = try sealedCredentials()
        let never = session(timing: timing)
        await never.start()
        try await Task.sleep(for: .milliseconds(200))
        #expect(never.state == .idle && wifi.restoredTo == ["Home"])

        wifi.network = "Home"
        let leaves = session(timing: timing)
        await leaves.start()
        leaves.tabletConnected()
        leaves.tabletDisconnected()
        leaves.tabletConnected()  // came back within the grace period
        try await Task.sleep(for: .milliseconds(200))
        #expect(leaves.state == .connected)
        leaves.tabletDisconnected()
        try await Task.sleep(for: .milliseconds(200))
        #expect(leaves.state == .idle)
        #expect(wifi.restoredTo == ["Home", "Home"])
    }
}
