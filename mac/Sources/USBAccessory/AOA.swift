import Foundation
import USBAccessoryShim

/// Android Open Accessory 2.0 (source.android.com "AOA"): the host asks an Android device to
/// re-enumerate as a USB accessory, then talks to the app through one pair of bulk pipes. No
/// developer mode, no adb, no network.
public enum AOA {
    public static let googleVendorID: UInt16 = 0x18D1
    /// 2D00 accessory, 2D01 accessory + adb; 2D02–2D05 add audio (never requested here).
    public static let accessoryProductIDs: ClosedRange<UInt16> = 0x2D00...0x2D05

    public static let getProtocolRequest: UInt8 = 51
    public static let sendStringRequest: UInt8 = 52
    public static let startRequest: UInt8 = 53

    /// Vendors whose devices are offered for the switch. Other USB devices are never sent vendor
    /// requests (an unknown request can upset some firmware).
    public static let androidVendorIDs: Set<UInt16> = [
        0x04E8,  // Samsung
        0x18D1,  // Google
        0x22B8,  // Motorola
        0x2717,  // Xiaomi
        0x2A70,  // OnePlus
        0x0B05,  // ASUS
        0x17EF,  // Lenovo
        0x1004,  // LG
        0x12D1,  // Huawei
        0x0FCE,  // Sony
    ]

    public static func isAccessoryMode(vendorID: UInt16, productID: UInt16) -> Bool {
        vendorID == googleVendorID && accessoryProductIDs.contains(productID)
    }

    /// GET_PROTOCOL's reply: little-endian version, 0 when unsupported.
    public static func protocolVersion(fromReply reply: Data) -> Int {
        reply.count >= 2 ? Int(reply[reply.startIndex]) | Int(reply[reply.startIndex + 1]) << 8 : 0
    }

    /// One SEND_STRING per identifying string (UTF-8, NUL-terminated), then START.
    public static func handshake(for identity: AccessoryIdentity) -> [VendorRequest] {
        identity.strings.enumerated().map { index, string in
            VendorRequest(request: sendStringRequest, index: UInt16(index), data: Data(string.utf8) + [0])
        } + [VendorRequest(request: startRequest, index: 0, data: Data())]
    }

    public static func needsZeroLengthPacket(length: Int, maxPacketSize: Int) -> Bool {
        T2MNeedsZeroLengthPacket(UInt(length), UInt(maxPacketSize))
    }
}

/// What the tablet app's accessory filter matches (android/app/src/main/res/xml/accessory_filter.xml).
public struct AccessoryIdentity: Hashable, Sendable {
    public var manufacturer = "Tab2Mac"
    public var model = "Tab2Mac Receiver"
    public var description = "Second display for your Mac"
    public var version = "1"
    /// Shown by Android when no app handles the accessory.
    public var uri = ""
    public var serial = "1"

    public init() {}

    public var strings: [String] { [manufacturer, model, description, version, uri, serial] }
}

public struct VendorRequest: Hashable, Sendable {
    public var request: UInt8
    public var index: UInt16
    public var data: Data
}

public enum AccessoryError: Error, CustomStringConvertible {
    case unsupported
    case usb(String)

    public var description: String {
        switch self {
        case .unsupported: "the device doesn't support Android Open Accessory"
        case .usb(let message): message
        }
    }
}

/// Performs the switch on a device identified by its IORegistry entry ID.
public enum AccessorySwitch {
    /// Checks GET_PROTOCOL, sends the identity and START. The device then disconnects and comes
    /// back as 18D1:2D00/2D01. Returns the AOA protocol version.
    @discardableResult
    public static func switchToAccessoryMode(entryID: UInt64, identity: AccessoryIdentity = AccessoryIdentity()) throws -> Int {
        let device: T2MUSBDevice
        do {
            device = try T2MUSBDevice.open(withRegistryEntryID: entryID)
        } catch {
            throw AccessoryError.usb(error.localizedDescription)
        }
        defer { device.close() }
        do {
            let reply = try device.vendorRequestIn(withRequest: AOA.getProtocolRequest, value: 0, index: 0, length: 2)
            let version = AOA.protocolVersion(fromReply: reply)
            guard version >= 1 else { throw AccessoryError.unsupported }
            for step in AOA.handshake(for: identity) {
                try device.vendorRequestOut(withRequest: step.request, value: 0, index: step.index, data: step.data)
            }
            return version
        } catch let error as AccessoryError {
            throw error
        } catch {
            throw AccessoryError.usb(error.localizedDescription)
        }
    }

    /// GET_PROTOCOL only: reports AOA support without changing anything on the device.
    public static func protocolVersion(entryID: UInt64) throws -> Int {
        do {
            let device = try T2MUSBDevice.open(withRegistryEntryID: entryID)
            defer { device.close() }
            return AOA.protocolVersion(fromReply: try device.vendorRequestIn(withRequest: AOA.getProtocolRequest, value: 0, index: 0, length: 2))
        } catch {
            throw AccessoryError.usb(error.localizedDescription)
        }
    }
}
