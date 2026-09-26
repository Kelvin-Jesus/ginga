import Testing
@testable import DirectLink

/// A radio whose network changes on a script: `autoJoinAfter` polls after leaving the tablet's
/// network, macOS joins `autoJoinTo` (as auto-join or the user would).
final class ScriptedRadio: WiFiRadio, @unchecked Sendable {
    var network: String?
    var autoJoinTo: String?
    var autoJoinAfter = Int.max
    var cachedNetworks: Set<String> = []
    var associateWorks = true
    var powerCycleJoins: String?
    var poweredOn = true
    private(set) var calls: [String] = []
    private var pollsSinceLeaving = 0

    init(network: String?) { self.network = network }

    func ssid() async -> String? {
        if network == nil {
            pollsSinceLeaving += 1
            if pollsSinceLeaving > autoJoinAfter { network = autoJoinTo }
        }
        return network
    }
    func disassociate() async {
        calls.append("disassociate")
        network = nil
        pollsSinceLeaving = 0
    }
    func associateFromLastScan(ssid: String) async -> Bool {
        calls.append("associate \(ssid)")
        guard cachedNetworks.contains(ssid), associateWorks else { return false }
        network = ssid
        return true
    }
    func isPoweredOn() async -> Bool { poweredOn }
    func cyclePower() async {
        calls.append("power cycle")
        network = powerCycleJoins
    }
}

@Suite("NetworkRestore")
struct NetworkRestoreTests {
    func restore(_ radio: ScriptedRadio) -> NetworkRestore {
        var timing = NetworkRestore.Timing()
        timing.poll = .milliseconds(500)  // 15 s of auto-join = 30 polls
        return NetworkRestore(radio: radio, timing: timing, sleep: { _ in })
    }

    /// The common case on the device: macOS auto-join brings the Mac home within seconds; the
    /// Mac does nothing else (a scan or association of its own only competes with it).
    @Test func waitsForAutoJoinWithoutInterfering() async {
        let radio = ScriptedRadio(network: "DIRECT-T2-0102")
        radio.autoJoinTo = "Home"
        radio.autoJoinAfter = 8  // ~4 s
        radio.cachedNetworks = ["Home"]
        #expect(await restore(radio).run(previous: "Home", leaving: "DIRECT-T2-0102") == .previous)
        #expect(radio.calls == ["disassociate"])
    }

    /// The user picked another network from the menu meanwhile: left alone, never power-cycled.
    @Test func keepsANetworkTheUserPicked() async {
        let radio = ScriptedRadio(network: "DIRECT-T2-0102")
        radio.autoJoinTo = "Phone hotspot"
        radio.autoJoinAfter = 20
        #expect(await restore(radio).run(previous: "Home", leaving: "DIRECT-T2-0102") == .other)
        #expect(radio.calls == ["disassociate"])
    }

    @Test func joinsThePreviousNetworkWhenAutoJoinDoesNot() async {
        let radio = ScriptedRadio(network: "DIRECT-T2-0102")
        radio.cachedNetworks = ["Home"]
        #expect(await restore(radio).run(previous: "Home", leaving: "DIRECT-T2-0102") == .previous)
        #expect(radio.calls == ["disassociate", "associate Home"])
    }

    @Test func cyclesTheRadioOnlyAsALastResort() async {
        let radio = ScriptedRadio(network: "DIRECT-T2-0102")
        radio.cachedNetworks = ["Home"]
        radio.associateWorks = false  // e.g. macOS won't hand the keychain password to the app
        radio.powerCycleJoins = "Home"
        #expect(await restore(radio).run(previous: "Home", leaving: "DIRECT-T2-0102") == .previous)
        #expect(radio.calls == ["disassociate", "associate Home", "power cycle"])
    }

    @Test func aRadioTheUserTurnedOffStaysOff() async {
        let radio = ScriptedRadio(network: "DIRECT-T2-0102")
        radio.poweredOn = false
        #expect(await restore(radio).run(previous: "Home", leaving: "DIRECT-T2-0102") == .none)
        #expect(!radio.calls.contains("power cycle"))
    }

    /// Auto-join put the Mac back on the tablet's network (still up): it never counts as home.
    @Test func theTabletsNetworkNeverCountsAsHome() async {
        let radio = ScriptedRadio(network: "DIRECT-T2-0102")
        radio.autoJoinTo = "DIRECT-T2-0102"
        radio.autoJoinAfter = 2
        radio.associateWorks = false
        radio.powerCycleJoins = "Home"
        #expect(await restore(radio).run(previous: "Home", leaving: "DIRECT-T2-0102") == .previous)
        #expect(radio.calls.first == "disassociate" && radio.calls.last == "power cycle")
    }

    /// No Wi‑Fi before (Ethernet only): leave the tablet's network and stay off Wi‑Fi.
    @Test func noPreviousNetworkJustLeaves() async {
        let radio = ScriptedRadio(network: "DIRECT-T2-0102")
        #expect(await restore(radio).run(previous: nil, leaving: "DIRECT-T2-0102") == .none)
        #expect(radio.calls == ["disassociate"])
    }

    /// The join failed and the Mac never left home: nothing to undo.
    @Test func neverLeftNothingToUndo() async {
        let radio = ScriptedRadio(network: "Home")
        #expect(await restore(radio).run(previous: "Home", leaving: "DIRECT-T2-0102") == .previous)
        #expect(radio.calls.isEmpty)
    }
}
