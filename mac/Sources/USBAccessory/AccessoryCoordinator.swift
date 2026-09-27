import Foundation
import os
import GingaCore
import Transport

/// Plug-and-play over USB (M6). Android devices the user approved are switched to accessory mode
/// when they appear; approved devices in accessory mode become stream connections (same protocol
/// as TCP). Everything is driven by USB notifications: nothing polls.
///
/// A stream connection shows the Mac's screen and accepts touch and pen input, so only devices
/// the user approved get one: any USB gadget can claim to be in accessory mode.
@MainActor
public final class AccessoryCoordinator {
    /// Android devices offered for approval: in normal mode, or already in accessory mode but not
    /// approved yet (e.g. switched by an earlier run).
    public private(set) var candidates: [UInt64: USBDeviceInfo] = [:]
    public private(set) var approvedSerials: Set<String>
    public private(set) var isEnabled: Bool
    public var onConnection: (@MainActor (MessageConnection) -> Void)?
    public var onChange: (@MainActor () -> Void)?

    private let events: any USBEventSource
    private let identity: AccessoryIdentity
    private let switcher: @Sendable (UInt64, AccessoryIdentity) throws -> Int
    private let linker: @MainActor (USBDeviceInfo) throws -> any ByteTransport
    private let retryDelay: Duration
    private let relinkDelay: Duration
    /// Serial → last switch attempt, so a device that won't switch isn't hammered.
    private var lastSwitch: [String: MediaTime] = [:]
    /// Open links by device, so revoking a tablet (or turning direct USB off) can end its session.
    private var links: [UInt64: MessageConnection] = [:]
    /// Approved accessory-mode devices currently attached, with the serial they were approved
    /// under, so a closed session can be followed by a new one on the same plug-in (the tablet
    /// reconnects without replugging).
    private var accessories: [UInt64: (device: USBDeviceInfo, serial: String)] = [:]
    private var started = false
    /// Vendor requests block for up to a second each: they run here, never on the main thread or
    /// Swift concurrency's cooperative pool.
    private let switchQueue = DispatchQueue(label: "dev.ginga.usb.switch", qos: .userInitiated)

    public init(
        isEnabled: Bool,
        approvedSerials: Set<String>,
        identity: AccessoryIdentity = AccessoryIdentity(),
        events: any USBEventSource = USBDeviceWatcher(),
        switcher: @escaping @Sendable (UInt64, AccessoryIdentity) throws -> Int = { try AccessorySwitch.switchToAccessoryMode(entryID: $0, identity: $1) },
        linker: @escaping @MainActor (USBDeviceInfo) throws -> any ByteTransport = { device in
            try AccessoryByteTransport(deviceEntryID: device.entryID, description: "usb-accessory:\(device.serialNumber ?? String(device.entryID))")
        },
        retryDelay: Duration = .milliseconds(200),
        relinkDelay: Duration = .seconds(1)
    ) {
        self.isEnabled = isEnabled
        self.approvedSerials = approvedSerials
        self.identity = identity
        self.events = events
        self.switcher = switcher
        self.linker = linker
        self.retryDelay = retryDelay
        self.relinkDelay = relinkDelay
    }

    public func start() {
        guard !started else { return }
        started = true
        events.start { [weak self] event in
            // The main queue is FIFO (separate Tasks are not): attach/detach keep their order.
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event) } }
        }
    }

    public func stop() {
        events.stop()
        started = false
        candidates = [:]
        links = [:]
    }

    /// Turning direct USB off also ends its sessions.
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            candidates.values.forEach(switchIfApproved)
        } else {
            links.values.forEach { $0.close(reason: "direct USB turned off") }
        }
        onChange?()
    }

    /// The user chose this device: switch it now and whenever it's plugged in again.
    public func approve(serial: String) {
        approvedSerials.insert(serial)
        lastSwitch[serial] = nil
        for device in candidates.values where device.serialNumber == serial {
            if device.isAccessoryMode, isEnabled {
                accessories[device.entryID] = (device, serial)  // already switched: link it now
                openLink(device, attempt: 0)
            } else {
                switchIfApproved(device)
            }
        }
        onChange?()
    }

    /// Forgets the device and ends its session, if one is open.
    public func revoke(serial: String) {
        approvedSerials.remove(serial)
        for (entryID, accessory) in accessories where accessory.serial == serial {
            accessories[entryID] = nil
            links[entryID]?.close(reason: "tablet no longer approved")
        }
        onChange?()
    }

    /// The approved serial an accessory-mode device stands for: its own, or, for a device whose
    /// serial changes in accessory mode, the single approved device switched moments ago.
    private func approvedSerial(for accessory: USBDeviceInfo) -> String? {
        if let serial = accessory.serialNumber, approvedSerials.contains(serial) { return serial }
        let justSwitched = lastSwitch.filter { approvedSerials.contains($0.key) && MediaTime.now() - $0.value < .seconds(10) }
        return justSwitched.count == 1 ? justSwitched.first?.key : nil
    }

    private func handle(_ event: USBDeviceEvent) {
        switch event {
        case .attached(let device) where device.isAccessoryMode:
            guard isEnabled, let serial = approvedSerial(for: device) else {
                Log.usb.info("usb.accessory-ignored entry=\(device.entryID) serial=\(device.serialNumber ?? "?", privacy: .public) reason=not-approved")
                if device.serialNumber != nil {  // listed, so the user can approve it without replugging
                    candidates[device.entryID] = device
                    onChange?()
                }
                return
            }
            Log.usb.info("usb.accessory-attached entry=\(device.entryID) serial=\(device.serialNumber ?? "?", privacy: .public)")
            accessories[device.entryID] = (device, serial)
            openLink(device, attempt: 0)
        case .attached(let device) where device.isAndroidCandidate:
            candidates[device.entryID] = device
            onChange?()
            switchIfApproved(device)
        case .attached:
            break
        case .detached(let entryID):
            links[entryID] = nil
            accessories.removeValue(forKey: entryID)
            if candidates.removeValue(forKey: entryID) != nil { onChange?() }
        }
    }

    private func switchIfApproved(_ device: USBDeviceInfo) {
        guard isEnabled, !device.isAccessoryMode, let serial = device.serialNumber, approvedSerials.contains(serial) else { return }
        if let last = lastSwitch[serial], MediaTime.now() - last < .seconds(10) { return }
        lastSwitch[serial] = .now()
        let identity = identity
        let entryID = device.entryID
        let switcher = switcher
        switchQueue.async {
            do {
                let version = try switcher(entryID, identity)
                Log.usb.info("usb.accessory-switch serial=\(serial, privacy: .public) aoa=\(version)")
            } catch {
                Log.usb.error("usb.accessory-switch-failed serial=\(serial, privacy: .public) reason=\(String(describing: error), privacy: .public)")
            }
        }
    }

    private func linkClosed(_ entryID: UInt64) {
        links[entryID] = nil
        guard isEnabled, let device = accessories[entryID]?.device else { return }
        let delay = relinkDelay
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.accessories[entryID] != nil else { return }  // unplugged or revoked meanwhile
            self.openLink(device, attempt: 0)
        }
    }

    private func openLink(_ device: USBDeviceInfo, attempt: Int) {
        guard isEnabled, accessories[device.entryID] != nil, links[device.entryID] == nil else { return }
        do {
            let entryID = device.entryID
            let transport = ObservedTransport(try linker(device)) { [weak self] in
                // The session ended (GOODBYE, error, tablet app closed its end): offer a fresh link
                // while the device stays plugged in, so the tablet can say HELLO again.
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.linkClosed(entryID) } }
            }
            let connection = MessageConnection(transport: transport)
            links[entryID] = connection
            Log.usb.info("usb.accessory-linked entry=\(entryID)")
            onConnection?(connection)
        } catch {
            // Interfaces are published a moment after the device itself.
            guard attempt < 15 else {
                Log.usb.error("usb.accessory-link-failed entry=\(device.entryID) reason=\(String(describing: error), privacy: .public)")
                return
            }
            let delay = retryDelay
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                self?.openLink(device, attempt: attempt + 1)
            }
        }
    }
}

/// Forwards to a transport and reports, once, that it was cancelled (the session is over).
final class ObservedTransport: ByteTransport, @unchecked Sendable {  // `cancelled` is locked
    private let base: any ByteTransport
    private let onCancel: @Sendable () -> Void
    private let cancelled = OSAllocatedUnfairLock(initialState: false)

    init(_ base: any ByteTransport, onCancel: @escaping @Sendable () -> Void) {
        self.base = base
        self.onCancel = onCancel
    }

    var endpointDescription: String { base.endpointDescription }

    func start(onReady: @escaping @Sendable () -> Void, onData: @escaping @Sendable (Data) -> Void, onEnd: @escaping @Sendable (ByteStreamEnd) -> Void) {
        base.start(onReady: onReady, onData: onData, onEnd: onEnd)
    }

    func write(_ data: Data, completion: @escaping @Sendable ((any Error)?) -> Void) {
        base.write(data, completion: completion)
    }

    func finish(completion: @escaping @Sendable () -> Void) {
        base.finish(completion: completion)
    }

    func cancel() {
        base.cancel()
        let first = cancelled.withLock { wasCancelled -> Bool in
            defer { wasCancelled = true }
            return !wasCancelled
        }
        if first { onCancel() }
    }
}
