import CoreLocation
import CoreWLAN
import Foundation
import os
import GingaCore

/// The Mac's Wi‑Fi through public API: CoreWLAN to join and leave, CoreLocation for the
/// permission macOS requires to see network names. Changes nothing unless asked.
public final class CoreWLANWiFi: NSObject, DirectWiFi, CLLocationManagerDelegate, @unchecked Sendable {  // the location manager and its continuation are only touched on the main queue
    private var locationManager: CLLocationManager?
    private var authorization: CheckedContinuation<Bool, Never>?

    public override init() {}

    private var interface: CWInterface? { CWWiFiClient.shared().interface() }

    public func authorize() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let manager = CLLocationManager()
                manager.delegate = self
                self.locationManager = manager
                switch manager.authorizationStatus {
                case .authorizedAlways, .authorized:
                    continuation.resume(returning: true)
                case .denied, .restricted:
                    continuation.resume(returning: false)
                default:
                    self.authorization = continuation  // answered in locationManagerDidChangeAuthorization
                    manager.requestWhenInUseAuthorization()
                }
            }
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined, let authorization else { return }
        self.authorization = nil
        authorization.resume(returning: status == .authorizedAlways || status == .authorized)
    }

    public var currentNetwork: String? { interface?.ssid() }

    public func join(ssid: String, password: String, timeout: Duration) async throws {
        guard interface != nil else { throw CoreWLANFailure("no Wi‑Fi interface") }
        let deadline = Date().addingTimeInterval(timeout.inSeconds)
        var lastFailure: String?
        while Date() < deadline {
            // The tablet's network can take a few seconds to show up in scans.
            lastFailure = await onRadioQueue { () -> String? in
                do {
                    guard let interface = self.interface, let network = try interface.scanForNetworks(withName: ssid).first else { return "not in range yet" }
                    try interface.associate(to: network, password: password)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
            if lastFailure == nil { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw CoreWLANFailure("couldn't join the tablet's network\(lastFailure.map { ": \($0)" } ?? "")")
    }

    public func address(timeout: Duration) async -> String? {
        guard let name = interface?.interfaceName else { return nil }
        let deadline = Date().addingTimeInterval(timeout.inSeconds)
        while Date() < deadline {
            if let address = Self.ipv4Address(of: name) { return address }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    public func restore(previous: String?, leaving: String) async -> RestoreOutcome {
        guard interface != nil else { return .none }
        return await NetworkRestore(radio: CoreWLANRadio(wifi: self)).run(previous: previous, leaving: leaving)
    }

    /// CoreWLAN calls block (a scan took 28 s on the device): never on Swift's shared threads.
    private let radioQueue = DispatchQueue(label: "dev.ginga.direct-link.wifi")

    fileprivate func onRadioQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            radioQueue.async { continuation.resume(returning: work()) }
        }
    }

    /// IPv4 of an interface, skipping link-local (169.254/16) addresses.
    static func ipv4Address(of name: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard String(validatingCString: entry.pointee.ifa_name) == name, let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if !text.hasPrefix("169.254.") { return text }
        }
        return nil
    }
}

/// `WiFiRadio` over CoreWLAN, every call on the Wi‑Fi queue.
private struct CoreWLANRadio: WiFiRadio {
    let wifi: CoreWLANWiFi
    private static var interface: CWInterface? { CWWiFiClient.shared().interface() }

    func ssid() async -> String? { await wifi.onRadioQueue { Self.interface?.ssid() } }
    func disassociate() async { await wifi.onRadioQueue { Self.interface?.disassociate() } }
    func associateFromLastScan(ssid: String) async -> Bool {
        await wifi.onRadioQueue {
            guard let interface = Self.interface, let network = interface.cachedScanResults()?.first(where: { $0.ssid == ssid }) else { return false }
            do {
                try interface.associate(to: network, password: nil)
                return true
            } catch {
                Log.directLink.info("direct.rejoin-failed code=\((error as NSError).code)")
                return false
            }
        }
    }
    func isPoweredOn() async -> Bool { await wifi.onRadioQueue { Self.interface?.powerOn() ?? false } }
    func cyclePower() async {
        await wifi.onRadioQueue {
            try? Self.interface?.setPower(false)
            try? Self.interface?.setPower(true)
        }
    }
}

struct CoreWLANFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
