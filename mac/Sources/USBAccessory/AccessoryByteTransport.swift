import Foundation
import os
import Tab2MacCore
import Transport
import USBAccessoryShim

/// The protocol's byte stream over an accessory-mode device's bulk pipes (M6). The same
/// `MessageConnection` framing, backpressure and HELLO/WELCOME run on top, exactly as over TCP.
public final class AccessoryByteTransport: ByteTransport, @unchecked Sendable {  // the link serialises on `queue`; `pending` is locked
    public let endpointDescription: String
    private let link: T2MAccessoryLink
    private let queue: DispatchQueue
    private struct Pending {
        var writes = 0
        var finish: (@Sendable () -> Void)?
    }
    private let pending = OSAllocatedUnfairLock(initialState: Pending())

    /// Opens the accessory interface of the device with this IORegistry entry ID.
    public init(deviceEntryID: UInt64, description: String) throws {
        let queue = DispatchQueue(label: "dev.tab2mac.usb.accessory", qos: .userInteractive)
        do {
            link = try T2MAccessoryLink.open(withDeviceRegistryEntryID: deviceEntryID, queue: queue)
        } catch {
            throw AccessoryError.usb(error.localizedDescription)
        }
        self.queue = queue
        endpointDescription = description
    }

    public func start(
        onReady: @escaping @Sendable () -> Void,
        onData: @escaping @Sendable (Data) -> Void,
        onEnd: @escaping @Sendable (ByteStreamEnd) -> Void
    ) {
        link.startReading(handler: { onData($0) }, closeHandler: { error in
            onEnd(error.map { .failed($0.localizedDescription) } ?? .remote)
        })
        queue.async { onReady() }  // the pipes are open: USB has no connect phase
    }

    public func write(_ data: Data, completion: @escaping @Sendable ((any Error)?) -> Void) {
        pending.withLock { $0.writes += 1 }
        link.write(data) { [weak self] error in
            completion(error)
            let finish = self?.pending.withLock { state -> (@Sendable () -> Void)? in
                state.writes -= 1
                guard state.writes == 0, let finish = state.finish else { return nil }
                state.finish = nil
                return finish
            }
            finish?()
        }
    }

    /// There is no FIN on USB: once queued writes are out, the stream is done.
    public func finish(completion: @escaping @Sendable () -> Void) {
        let now = pending.withLock { state -> Bool in
            if state.writes == 0 { return true }
            state.finish = completion
            return false
        }
        if now { queue.async { completion() } }
    }

    public func cancel() {
        link.close()
    }
}
