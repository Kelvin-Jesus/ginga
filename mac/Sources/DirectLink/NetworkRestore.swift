import Foundation

/// Where the Mac ended up after leaving the tablet's network.
public enum RestoreOutcome: String, Equatable, Sendable {
    /// Back on the network it was on before.
    case previous
    /// On another network (macOS auto-join or the user picked it; left alone).
    case other
    /// On no Wi‑Fi network. Normal when there was none before (Ethernet only).
    case none
}

/// The few radio operations the way home needs.
protocol WiFiRadio: Sendable {
    /// The network the Mac is on, nil when on none.
    func ssid() async -> String?
    func disassociate() async
    /// Joins `ssid` from the last scan results (no new scan), with the password macOS holds.
    /// False when the network isn't in them or the association failed.
    func associateFromLastScan(ssid: String) async -> Bool
    func isPoweredOn() async -> Bool
    func cyclePower() async
}

/// Leaves the tablet's network and gets the Mac back to its own, cooperating with macOS.
///
/// Once the Mac is off the tablet's network, macOS auto-join rejoins a known network within a
/// few seconds. Anything done meanwhile competes with it: on the device, a scan of ours kept
/// auto-join's association from finishing and took 28 s itself. So it waits first, then joins
/// the previous network from the last scan results, and only cycles the radio (which makes macOS
/// join its preferred networks, as after waking) when the Mac is on no network at all, so a
/// network the user picked meanwhile is never dropped.
struct NetworkRestore: Sendable {
    struct Timing: Sendable {
        var autoJoin: Duration = .seconds(15)
        var associate: Duration = .seconds(8)
        var afterPowerCycle: Duration = .seconds(20)
        var poll: Duration = .milliseconds(500)
    }

    let radio: any WiFiRadio
    var timing = Timing()
    var sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }

    /// - Parameters:
    ///   - previous: the network the Mac was on before joining the tablet's (nil if none).
    ///   - leaving: the tablet's network, which never counts as "back".
    func run(previous: String?, leaving: String) async -> RestoreOutcome {
        if await radio.ssid() == leaving {
            await radio.disassociate()
        } else if let outcome = await settled(previous: previous, leaving: leaving) {
            return outcome  // never got onto the tablet's network (the join failed): nothing to undo
        }
        guard let previous, previous != leaving else { return .none }  // no Wi‑Fi before: stay off it

        if let outcome = await settle(previous: previous, leaving: leaving, within: timing.autoJoin) { return outcome }

        if await radio.ssid() == nil, await radio.associateFromLastScan(ssid: previous),
           let outcome = await settle(previous: previous, leaving: leaving, within: timing.associate) {
            return outcome
        }

        // Back on the tablet's network (auto-join, while the tablet still offered it)? Leave again.
        if await radio.ssid() == leaving { await radio.disassociate() }
        guard await radio.ssid() == nil, await radio.isPoweredOn() else { return await settled(previous: previous, leaving: leaving) ?? .none }
        await radio.cyclePower()
        return await settle(previous: previous, leaving: leaving, within: timing.afterPowerCycle) ?? .none
    }

    private func settled(previous: String?, leaving: String) async -> RestoreOutcome? {
        guard let current = await radio.ssid(), current != leaving else { return nil }
        return current == previous ? .previous : .other
    }

    /// Polls until the Mac is on a network other than the tablet's, or `within` passes.
    private func settle(previous: String, leaving: String, within: Duration) async -> RestoreOutcome? {
        let polls = max(1, Int((within / timing.poll).rounded(.up)))
        for _ in 0..<polls {
            if let outcome = await settled(previous: previous, leaving: leaving) { return outcome }
            await sleep(timing.poll)
        }
        return await settled(previous: previous, leaving: leaving)
    }
}
