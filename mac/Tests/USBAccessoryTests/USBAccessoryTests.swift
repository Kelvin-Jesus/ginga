import Foundation
import Testing
import Transport
@testable import USBAccessory

@Suite("AOA")
struct AOATests {
    @Test func handshakeSendsSixNulTerminatedStringsThenStart() {
        let steps = AOA.handshake(for: AccessoryIdentity())
        #expect(steps.count == 7)
        #expect(steps.prefix(6).map(\.request) == Array(repeating: 52, count: 6))
        #expect(steps.prefix(6).map(\.index) == [0, 1, 2, 3, 4, 5])
        #expect(steps[0].data == Data("Ginga".utf8) + [0])
        #expect(steps[1].data == Data("Ginga Receiver".utf8) + [0])  // must match the tablet's accessory filter
        #expect(steps[4].data == Data([0]))  // empty URI is still sent
        #expect(steps[6] == VendorRequest(request: 53, index: 0, data: Data()))
    }

    @Test func protocolVersionIsLittleEndianAndZeroWhenMissing() {
        #expect(AOA.protocolVersion(fromReply: Data([2, 0])) == 2)
        #expect(AOA.protocolVersion(fromReply: Data([1, 1])) == 257)
        #expect(AOA.protocolVersion(fromReply: Data([2])) == 0)
        #expect(AOA.protocolVersion(fromReply: Data()) == 0)
    }

    @Test func accessoryModeAndCandidates() {
        let tablet = USBDeviceInfo(entryID: 1, vendorID: 0x04E8, productID: 0x6864, name: "SAMSUNG_Android", serialNumber: "R52Y80EE15V")
        #expect(tablet.isAndroidCandidate && !tablet.isAccessoryMode)
        let accessory = USBDeviceInfo(entryID: 2, vendorID: 0x18D1, productID: 0x2D01)
        #expect(accessory.isAccessoryMode && !accessory.isAndroidCandidate)
        let keyboard = USBDeviceInfo(entryID: 3, vendorID: 0x05AC, productID: 0x0250)
        #expect(!keyboard.isAccessoryMode && !keyboard.isAndroidCandidate)  // never sent vendor requests
        #expect(!USBDeviceInfo(entryID: 4, vendorID: 0x18D1, productID: 0x4EE1).isAccessoryMode)  // a Pixel in MTP mode
    }

    @Test func zeroLengthPacketOnlyOnExactPacketMultiples() {
        #expect(AOA.needsZeroLengthPacket(length: 512, maxPacketSize: 512))
        #expect(AOA.needsZeroLengthPacket(length: 16384, maxPacketSize: 512))
        #expect(!AOA.needsZeroLengthPacket(length: 513, maxPacketSize: 512))
        #expect(!AOA.needsZeroLengthPacket(length: 0, maxPacketSize: 512))
        #expect(!AOA.needsZeroLengthPacket(length: 1024, maxPacketSize: 0))
    }
}

/// Scripted USB events.
final class FakeUSBEvents: USBEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (USBDeviceEvent) -> Void)?
    func start(_ handler: @escaping @Sendable (USBDeviceEvent) -> Void) { lock.withLock { self.handler = handler } }
    func stop() { lock.withLock { handler = nil } }
    func send(_ event: USBDeviceEvent) { lock.withLock { handler }?(event) }
}

final class Recorder<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func append(_ item: T) { lock.withLock { items.append(item) } }
    var values: [T] { lock.withLock { items } }
}

/// A transport that never connects anywhere (the coordinator only hands it on); counts cancels.
final class InertTransport: ByteTransport, @unchecked Sendable {
    let endpointDescription = "inert"
    private let cancels: Recorder<Int>?
    init(cancels: Recorder<Int>? = nil) { self.cancels = cancels }
    func start(onReady: @escaping @Sendable () -> Void, onData: @escaping @Sendable (Data) -> Void, onEnd: @escaping @Sendable (ByteStreamEnd) -> Void) {}
    func write(_ data: Data, completion: @escaping @Sendable ((any Error)?) -> Void) { completion(nil) }
    func finish(completion: @escaping @Sendable () -> Void) { completion() }
    func cancel() { cancels?.append(1) }
}

@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

@MainActor
@Suite("AccessoryCoordinator")
struct AccessoryCoordinatorTests {
    let events = FakeUSBEvents()
    let switches = Recorder<UInt64>()
    let tablet = USBDeviceInfo(entryID: 10, vendorID: 0x04E8, productID: 0x6864, name: "SAMSUNG_Android", serialNumber: "R52Y80EE15V")
    /// The same tablet after it switched: Google's accessory IDs, same serial.
    let tabletAccessory = USBDeviceInfo(entryID: 13, vendorID: 0x18D1, productID: 0x2D00, serialNumber: "R52Y80EE15V")
    let cancels = Recorder<Int>()

    func coordinator(enabled: Bool = true, approved: Set<String> = ["R52Y80EE15V"], linkFailures: Int = 0) -> (AccessoryCoordinator, Recorder<MessageConnection>) {
        let switches = switches
        let cancels = cancels
        let failures = Recorder<Int>()
        let coordinator = AccessoryCoordinator(
            isEnabled: enabled, approvedSerials: approved, events: events,
            switcher: { entryID, _ in switches.append(entryID); return 2 },
            linker: { _ in
                if failures.values.count < linkFailures {
                    failures.append(1)
                    throw AccessoryError.usb("interfaces not published yet")
                }
                return InertTransport(cancels: cancels)
            },
            retryDelay: .milliseconds(1),
            relinkDelay: .milliseconds(5)
        )
        let connections = Recorder<MessageConnection>()
        coordinator.onConnection = { connections.append($0) }
        coordinator.start()
        return (coordinator, connections)
    }

    @Test func anApprovedTabletIsSwitchedWhenPluggedIn() async {
        let (coordinator, _) = coordinator()
        events.send(.attached(tablet))
        #expect(await eventually { switches.values == [10] })
        #expect(coordinator.candidates[10] == tablet)
    }

    @Test func otherDevicesAreOnlyListed() async throws {
        let (coordinator, _) = coordinator(approved: [])
        events.send(.attached(tablet))
        #expect(await eventually { coordinator.candidates[10] != nil })
        try await Task.sleep(for: .milliseconds(20))
        #expect(switches.values.isEmpty)
        coordinator.approve(serial: "R52Y80EE15V")  // the user picks it
        #expect(await eventually { switches.values == [10] })
    }

    @Test func nothingHappensWhileDisabled() async throws {
        let (coordinator, connections) = coordinator(enabled: false)
        events.send(.attached(tablet))
        events.send(.attached(USBDeviceInfo(entryID: 11, vendorID: 0x18D1, productID: 0x2D01)))
        try await Task.sleep(for: .milliseconds(20))
        #expect(switches.values.isEmpty && connections.values.isEmpty)
        coordinator.setEnabled(true)
        #expect(await eventually { switches.values == [10] })
    }

    @Test func aDeviceThatDoesntSwitchIsNotHammered() async throws {
        let (coordinator, _) = coordinator()
        defer { coordinator.stop() }
        events.send(.attached(tablet))
        events.send(.detached(entryID: 10))
        events.send(.attached(tablet))  // re-enumerated in normal mode again right away
        try await Task.sleep(for: .milliseconds(30))
        #expect(switches.values == [10])
    }

    /// Disconnect → Connect on the tablet (or a first session that never started) works without
    /// replugging: once a session ends, a fresh link is offered while the device stays attached.
    @Test func aClosedSessionIsFollowedByAFreshLinkWhileAttached() async throws {
        let (coordinator, connections) = coordinator()
        defer { coordinator.stop() }
        events.send(.attached(tabletAccessory))
        #expect(await eventually { connections.values.count == 1 })
        connections.values[0].close(reason: "tablet said goodbye")
        #expect(await eventually { connections.values.count == 2 })
        events.send(.detached(entryID: 13))
        try await Task.sleep(for: .milliseconds(20))
        try #require(connections.values.count == 2)
        connections.values[1].close(reason: "unplugged")
        try await Task.sleep(for: .milliseconds(30))
        #expect(connections.values.count == 2)  // gone: no relink
    }

    /// A stream connection shows the screen and takes input: any USB gadget can claim accessory
    /// mode, so only approved devices get one.
    @Test func anAccessoryThatWasNotApprovedGetsNoConnection() async throws {
        let (coordinator, connections) = coordinator(approved: ["R52Y80EE15V"])
        defer { coordinator.stop() }
        events.send(.attached(USBDeviceInfo(entryID: 20, vendorID: 0x18D1, productID: 0x2D01, serialNumber: "SOMETHING-ELSE")))
        events.send(.attached(USBDeviceInfo(entryID: 21, vendorID: 0x18D1, productID: 0x2D00)))  // no serial, nothing switched
        try await Task.sleep(for: .milliseconds(30))
        #expect(connections.values.isEmpty)
    }

    /// A tablet an earlier run left in accessory mode is listed, and approving it links it at once
    /// (no replugging).
    @Test func anUnapprovedAccessoryIsListedAndLinksOnApproval() async throws {
        let (coordinator, connections) = coordinator(approved: [])
        defer { coordinator.stop() }
        events.send(.attached(tabletAccessory))
        #expect(await eventually { coordinator.candidates[13] != nil })
        #expect(connections.values.isEmpty)
        coordinator.approve(serial: "R52Y80EE15V")
        #expect(await eventually { connections.values.count == 1 })
        #expect(switches.values.isEmpty)  // already in accessory mode: nothing to switch
    }

    /// Should a device report another serial in accessory mode, the approved device switched a
    /// moment ago is taken to be it.
    @Test func aDeviceJustSwitchedIsAcceptedEvenWithoutItsSerial() async throws {
        let (coordinator, connections) = coordinator()
        defer { coordinator.stop() }
        events.send(.attached(tablet))
        #expect(await eventually { switches.values == [10] })
        events.send(.detached(entryID: 10))
        events.send(.attached(USBDeviceInfo(entryID: 22, vendorID: 0x18D1, productID: 0x2D00)))
        #expect(await eventually { connections.values.count == 1 })
    }

    @Test func revokingATabletEndsItsSessionAndItIsNotRelinked() async throws {
        let (coordinator, connections) = coordinator()
        defer { coordinator.stop() }
        events.send(.attached(tabletAccessory))
        #expect(await eventually { connections.values.count == 1 })
        coordinator.revoke(serial: "R52Y80EE15V")
        #expect(await eventually { cancels.values.count == 1 })  // the link was closed
        try await Task.sleep(for: .milliseconds(30))
        #expect(connections.values.count == 1)  // and no fresh one offered
    }

    @Test func turningDirectUSBOffEndsItsSessions() async throws {
        let (coordinator, connections) = coordinator()
        defer { coordinator.stop() }
        events.send(.attached(tabletAccessory))
        #expect(await eventually { connections.values.count == 1 })
        coordinator.setEnabled(false)
        #expect(await eventually { cancels.values.count == 1 })
        try await Task.sleep(for: .milliseconds(30))
        #expect(connections.values.count == 1)
    }

    @Test func accessoryModeDevicesBecomeConnectionsOncePerAttach() async {
        let (coordinator, connections) = coordinator(linkFailures: 3)  // interfaces show up a moment later
        defer { coordinator.stop() }
        let accessory = USBDeviceInfo(entryID: 12, vendorID: 0x18D1, productID: 0x2D01, serialNumber: "R52Y80EE15V")
        events.send(.attached(accessory))
        #expect(await eventually { connections.values.count == 1 })
        events.send(.attached(accessory))  // duplicate notification
        try? await Task.sleep(for: .milliseconds(20))
        #expect(connections.values.count == 1)
        events.send(.detached(entryID: 12))
        events.send(.attached(accessory))  // replugged
        #expect(await eventually { connections.values.count == 2 })
    }
}

@Suite("USBDeviceWatcher")
struct USBDeviceWatcherTests {
    /// Real IOKit, read-only. While started, IOKit's callbacks keep the watcher alive; `stop()`
    /// releases it, so nothing can call into a freed watcher and nothing leaks.
    @Test func stopReleasesTheWatcher() async throws {
        weak var released: USBDeviceWatcher?
        do {
            let watcher = USBDeviceWatcher()
            released = watcher
            watcher.start { _ in }
            try await Task.sleep(for: .milliseconds(50))
            watcher.stop()
        }
        #expect(released == nil)
    }
}
