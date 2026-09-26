import CoreBluetooth
import Foundation

/// The tablet's GATT service (PROTOCOL.md §6b), read and written with CoreBluetooth.
public enum DirectLinkUUIDs {
    // Computed: CBUUID isn't Sendable, so no shared instances.
    public static var service: CBUUID { CBUUID(string: "5432D1EC-7D1A-4F5B-9A6E-0E2A6D3C0001") }
    public static var credentials: CBUUID { CBUUID(string: "5432D1EC-7D1A-4F5B-9A6E-0E2A6D3C0002") }
    public static var address: CBUUID { CBUUID(string: "5432D1EC-7D1A-4F5B-9A6E-0E2A6D3C0003") }
}

/// Scans only while asked (the user clicked), connects to the first tablet offering the service,
/// reads the sealed credentials and writes the sealed address back.
public final class BluetoothCredentialChannel: NSObject, DirectCredentialChannel, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {  // CoreBluetooth calls back on `queue`; state is only touched there
    public enum Failure: Error, CustomStringConvertible {
        case unavailable(String)
        case timedOut
        case gatt(String)
        public var description: String {
            switch self {
            case .unavailable(let reason): "Bluetooth unavailable: \(reason)"
            case .timedOut: "no tablet offering a direct connection nearby (start it on the tablet first)"
            case .gatt(let reason): "Bluetooth: \(reason)"
            }
        }
    }

    private let queue = DispatchQueue(label: "dev.tab2mac.direct-link.bluetooth")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var credentials: CBCharacteristic?
    private var address: CBCharacteristic?
    private var readContinuation: CheckedContinuation<Data, any Error>?
    private var writeContinuation: CheckedContinuation<Void, any Error>?

    public override init() {}

    public func readCredentials(timeout: Duration) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.readContinuation = continuation
                self.central = CBCentralManager(delegate: self, queue: self.queue)  // state change starts the scan
                self.queue.asyncAfter(deadline: .now() + timeout.inSeconds) { self.finishRead(.failure(Failure.timedOut)) }
            }
        }
    }

    public func writeAddress(_ value: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                guard let peripheral = self.peripheral, let address = self.address else {
                    continuation.resume(throwing: Failure.gatt("not connected"))
                    return
                }
                self.writeContinuation = continuation
                peripheral.writeValue(value, for: address, type: .withResponse)
                self.queue.asyncAfter(deadline: .now() + 10) { self.finishWrite(Failure.timedOut) }
            }
        }
    }

    public func close() {
        queue.async {
            self.central?.stopScan()
            if let peripheral = self.peripheral { self.central?.cancelPeripheralConnection(peripheral) }
            self.peripheral = nil
            self.central = nil
            self.finishRead(.failure(Failure.gatt("closed")))
            self.finishWrite(Failure.gatt("closed"))
        }
    }

    private func finishRead(_ result: Result<Data, any Error>) {
        guard let continuation = readContinuation else { return }
        readContinuation = nil
        central?.stopScan()
        continuation.resume(with: result)
    }

    private func finishWrite(_ error: (any Error)?) {
        guard let continuation = writeContinuation else { return }
        writeContinuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    // MARK: CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: [DirectLinkUUIDs.service])
        case .unauthorized:
            finishRead(.failure(Failure.unavailable("Tab2Mac isn't allowed to use Bluetooth (System Settings › Privacy & Security › Bluetooth)")))
        case .poweredOff:
            finishRead(.failure(Failure.unavailable("Bluetooth is off")))
        case .unsupported:
            finishRead(.failure(Failure.unavailable("this Mac has no Bluetooth LE")))
        default:
            break  // .unknown / .resetting: wait
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([DirectLinkUUIDs.service])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        finishRead(.failure(Failure.gatt(error.map { String(describing: $0) } ?? "connection failed")))
    }

    // MARK: CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == DirectLinkUUIDs.service }) else {
            finishRead(.failure(Failure.gatt("service missing")))
            return
        }
        peripheral.discoverCharacteristics([DirectLinkUUIDs.credentials, DirectLinkUUIDs.address], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        credentials = service.characteristics?.first { $0.uuid == DirectLinkUUIDs.credentials }
        address = service.characteristics?.first { $0.uuid == DirectLinkUUIDs.address }
        guard let credentials, address != nil else {
            finishRead(.failure(Failure.gatt("characteristics missing")))
            return
        }
        peripheral.readValue(for: credentials)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == DirectLinkUUIDs.credentials else { return }
        if let error { return finishRead(.failure(Failure.gatt(String(describing: error)))) }
        finishRead(.success(characteristic.value ?? Data()))
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == DirectLinkUUIDs.address else { return }
        finishWrite(error.map { Failure.gatt(String(describing: $0)) })
    }
}
