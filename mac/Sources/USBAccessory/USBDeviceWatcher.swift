import Foundation
import IOKit
import os
import GingaCore

extension Log {
    public static let usb = Logger(subsystem: subsystem, category: "usb")
}

/// A USB device as IOKit publishes it.
public struct USBDeviceInfo: Hashable, Sendable {
    public var entryID: UInt64
    public var vendorID: UInt16
    public var productID: UInt16
    public var name: String?
    public var serialNumber: String?

    public init(entryID: UInt64, vendorID: UInt16, productID: UInt16, name: String? = nil, serialNumber: String? = nil) {
        self.entryID = entryID
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.serialNumber = serialNumber
    }

    public var isAccessoryMode: Bool { AOA.isAccessoryMode(vendorID: vendorID, productID: productID) }
    public var isAndroidCandidate: Bool { !isAccessoryMode && AOA.androidVendorIDs.contains(vendorID) }
}

public enum USBDeviceEvent: Sendable {
    case attached(USBDeviceInfo)
    case detached(entryID: UInt64)
}

/// A source of USB attach/detach events (IOKit in the app, scripted in tests).
public protocol USBEventSource: AnyObject, Sendable {
    /// Existing devices are reported as `.attached` first.
    func start(_ handler: @escaping @Sendable (USBDeviceEvent) -> Void)
    func stop()
}

/// Reports USB devices appearing and disappearing, from IOKit notifications (nothing polls).
///
/// While started, the watcher keeps itself alive (IOKit holds it as the callbacks' context), so
/// a notification can never reach a freed watcher; `stop()` lets it go.
public final class USBDeviceWatcher: USBEventSource, @unchecked Sendable {  // IOKit state is only touched on `queue`
    public typealias Event = USBDeviceEvent

    private let queue = DispatchQueue(label: "dev.ginga.usb.watcher", qos: .utility)
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var handler: (@Sendable (Event) -> Void)?
    /// The reference IOKit's callbacks use, released by `stop()`.
    private var context: Unmanaged<USBDeviceWatcher>?

    public init() {}

    /// Existing devices are reported as `.attached` first.
    public func start(_ handler: @escaping @Sendable (Event) -> Void) {
        queue.async { [self] in
            guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
            self.handler = handler
            self.port = port
            IONotificationPortSetDispatchQueue(port, queue)
            let retained = Unmanaged.passRetained(self)
            self.context = retained
            let context = retained.toOpaque()
            for (type, callback) in [(kIOFirstMatchNotification, Self.matched), (kIOTerminatedNotification, Self.terminated)] {
                var iterator: io_iterator_t = 0
                let status = IOServiceAddMatchingNotification(port, type, IOServiceMatching("IOUSBHostDevice"), callback, context, &iterator)
                guard status == KERN_SUCCESS else {
                    Log.usb.error("usb.watch-failed status=\(status)")
                    continue
                }
                iterators.append(iterator)
                callback(context, iterator)  // drains current devices and arms the notification
            }
        }
    }

    /// Call from outside the watcher's callbacks (it waits for its queue).
    public func stop() {
        queue.sync {
            iterators.forEach { IOObjectRelease($0) }
            iterators = []
            if let port { IONotificationPortDestroy(port) }
            port = nil
            handler = nil
            // The caller still holds a reference, so this never frees the watcher mid-call.
            context?.release()
            context = nil
        }
    }

    private static let matched: IOServiceMatchingCallback = { context, iterator in
        guard let context else { return }
        let watcher = Unmanaged<USBDeviceWatcher>.fromOpaque(context).takeUnretainedValue()
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let info = USBDeviceWatcher.info(for: service) { watcher.handler?(.attached(info)) }
            IOObjectRelease(service)
        }
    }

    private static let terminated: IOServiceMatchingCallback = { context, iterator in
        guard let context else { return }
        let watcher = Unmanaged<USBDeviceWatcher>.fromOpaque(context).takeUnretainedValue()
        while case let service = IOIteratorNext(iterator), service != 0 {
            var entryID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS { watcher.handler?(.detached(entryID: entryID)) }
            IOObjectRelease(service)
        }
    }

    /// A one-off snapshot of connected USB devices (for the CLI).
    public static func currentDevices() -> [USBDeviceInfo] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var devices: [USBDeviceInfo] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let info = info(for: service) { devices.append(info) }
            IOObjectRelease(service)
        }
        return devices
    }

    static func info(for service: io_service_t) -> USBDeviceInfo? {
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
              let vendor = property(service, "idVendor") as? NSNumber,
              let product = property(service, "idProduct") as? NSNumber else { return nil }
        return USBDeviceInfo(
            entryID: entryID, vendorID: vendor.uint16Value, productID: product.uint16Value,
            name: property(service, "USB Product Name") as? String,
            serialNumber: property(service, "USB Serial Number") as? String
        )
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
