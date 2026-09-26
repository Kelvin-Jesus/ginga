import Foundation
import Network
import os
import Tab2MacCore
import Tab2MacProtocol

extension Log {
    public static let transport = Logger(subsystem: subsystem, category: "transport")
}

public struct ConnectionStatistics: Hashable, Sendable {
    public var bytesSent = 0
    public var bytesReceived = 0
    public var messagesSent = 0
    public var messagesReceived = 0
    public var videoFramesSent = 0
    public var videoFramesInFlight = 0
}

/// How a byte stream ended.
public enum ByteStreamEnd: Sendable, Equatable {
    case remote
    case failed(String)
    case cancelled
}

/// A reliable, ordered byte stream under the message framing: TCP (Network.framework) or USB
/// bulk pipes in accessory mode (M6). Callbacks run on the transport's own serial queue.
public protocol ByteTransport: AnyObject, Sendable {
    var endpointDescription: String { get }
    func start(
        onReady: @escaping @Sendable () -> Void,
        onData: @escaping @Sendable (Data) -> Void,
        onEnd: @escaping @Sendable (ByteStreamEnd) -> Void
    )
    /// Queues bytes; `completion` runs once the link has taken them (or failed).
    func write(_ data: Data, completion: @escaping @Sendable ((any Error)?) -> Void)
    /// Flushes queued writes, then ends the stream (TCP: FIN).
    func finish(completion: @escaping @Sendable () -> Void)
    func cancel()
}

/// TCP via Network.framework.
public final class NetworkByteTransport: ByteTransport, @unchecked Sendable {  // NWConnection is thread-safe
    public let endpointDescription: String
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "dev.tab2mac.transport.connection", qos: .userInteractive)

    public init(connection: NWConnection) {
        self.connection = connection
        self.endpointDescription = String(describing: connection.endpoint)
    }

    public func start(
        onReady: @escaping @Sendable () -> Void,
        onData: @escaping @Sendable (Data) -> Void,
        onEnd: @escaping @Sendable (ByteStreamEnd) -> Void
    ) {
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                onReady()
                self?.receive(onData: onData, onEnd: onEnd)
            case .failed(let error):
                onEnd(.failed(String(describing: error)))
            case .cancelled:
                onEnd(.cancelled)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(onData: @escaping @Sendable (Data) -> Void, onEnd: @escaping @Sendable (ByteStreamEnd) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] content, _, isComplete, error in
            if let content, !content.isEmpty { onData(content) }
            if let error {
                onEnd(.failed(String(describing: error)))
            } else if isComplete {
                onEnd(.remote)
            } else {
                self?.receive(onData: onData, onEnd: onEnd)
            }
        }
    }

    public func write(_ data: Data, completion: @escaping @Sendable ((any Error)?) -> Void) {
        connection.send(content: data, completion: .contentProcessed { completion($0) })
    }

    public func finish(completion: @escaping @Sendable () -> Void) {
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in completion() })
    }

    public func cancel() {
        connection.cancel()
    }

    /// The peer's leaf certificate (DER) once TLS is established; nil without TLS or before.
    public func peerCertificate() -> Data? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { return nil }
        var leaf: Data?
        sec_protocol_metadata_access_peer_certificate_chain(metadata.securityProtocolMetadata) { certificate in
            if leaf == nil { leaf = SecCertificateCopyData(sec_certificate_copy_ref(certificate).takeRetainedValue()) as Data }
        }
        return leaf
    }
}

/// A framed, bidirectional message connection over a reliable byte stream (`ByteTransport`: TCP
/// today, USB bulk pipes in accessory mode from M6).
///
/// Video backpressure: at most `maxVideoInFlight` VIDEO_FRAMEs may be queued in the transport.
/// Callers check `canAcceptVideo` *before encoding* and skip capture frames when it is false —
/// encoded frames are never dropped, because every P-frame depends on its predecessor.
///
/// `@unchecked Sendable`: the transport is thread-safe; mutable state lives in `state`.
public final class MessageConnection: @unchecked Sendable {
    public enum CloseReason: Sendable, Equatable {
        case local(String)
        case remote
        case failed(String)
        case protocolError(String)
    }

    private struct State {
        var statistics = ConnectionStatistics()
        var closed = false
        var onMessage: (@Sendable (Message) -> Void)?
        var onClose: (@Sendable (CloseReason) -> Void)?
        var onReady: (@Sendable () -> Void)?
    }

    public let maxVideoInFlight: Int
    public var endpointDescription: String { transport.endpointDescription }
    private let transport: any ByteTransport
    private let timers = DispatchQueue(label: "dev.tab2mac.transport.connection-timers", qos: .utility)
    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    /// Touched only by the receive path, so parsing never holds the lock that `send` and
    /// `canAcceptVideo` take for every video frame.
    private let parser = OSAllocatedUnfairLock(initialState: FrameParser())

    public init(transport: any ByteTransport, maxVideoInFlight: Int = 2) {
        self.transport = transport
        self.maxVideoInFlight = maxVideoInFlight
    }

    public convenience init(connection: NWConnection, maxVideoInFlight: Int = 2) {
        self.init(transport: NetworkByteTransport(connection: connection), maxVideoInFlight: maxVideoInFlight)
    }

    /// Opens a client connection (used by `t2m receive` and the tests).
    public static func connect(host: String, port: UInt16, maxVideoInFlight: Int = 2) -> MessageConnection {
        let parameters = NWParameters.tcp
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options { tcp.noDelay = true }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        return MessageConnection(connection: connection, maxVideoInFlight: maxVideoInFlight)
    }

    public var statistics: ConnectionStatistics { state.withLockUnchecked { $0.statistics } }

    public var canAcceptVideo: Bool {
        state.withLockUnchecked { !$0.closed && $0.statistics.videoFramesInFlight < maxVideoInFlight }
    }

    /// Handlers run on the transport's private queue. Set them before `start()`.
    public func setHandlers(
        onReady: (@Sendable () -> Void)? = nil,
        onMessage: @escaping @Sendable (Message) -> Void,
        onClose: @escaping @Sendable (CloseReason) -> Void
    ) {
        state.withLockUnchecked { state in
            state.onReady = onReady
            state.onMessage = onMessage
            state.onClose = onClose
        }
    }

    public func start() {
        transport.start(
            onReady: { [weak self] in
                guard let self else { return }
                Log.transport.info("connection.ready endpoint=\(self.endpointDescription, privacy: .public)")
                self.state.withLockUnchecked { $0.onReady }?()
            },
            onData: { [weak self] content in
                guard let self else { return }
                do {
                    try self.deliver(content)
                } catch {
                    let reason = String(describing: error)
                    self.send(.error(ErrorMessage(code: "bad-frame", message: reason)))
                    self.finish(.protocolError(reason))
                }
            },
            onEnd: { [weak self] end in
                switch end {
                case .remote: self?.finish(.remote)
                case .failed(let reason): self?.finish(.failed(reason))
                case .cancelled: self?.finish(.local("cancelled"))
                }
            }
        )
    }

    public func send(_ message: Message) {
        let data = MessageCodec.frame(message)
        let isVideo: Bool
        if case .videoFrame = message { isVideo = true } else { isVideo = false }
        let accepted = state.withLockUnchecked { state -> Bool in
            guard !state.closed else { return false }
            state.statistics.bytesSent += data.count
            state.statistics.messagesSent += 1
            if isVideo {
                state.statistics.videoFramesSent += 1
                state.statistics.videoFramesInFlight += 1
            }
            return true
        }
        guard accepted else { return }
        transport.write(data) { [weak self] error in
            if isVideo { self?.state.withLockUnchecked { $0.statistics.videoFramesInFlight -= 1 } }
            if let error { self?.finish(.failed(String(describing: error))) }
        }
    }

    /// Flushes everything already sent (e.g. ERROR, GOODBYE), then closes (TCP: with a FIN).
    public func close(reason: String) {
        guard !state.withLockUnchecked({ $0.closed }) else { return }
        transport.finish { [weak self] in self?.finish(.local(reason)) }
        // Never hang on a peer that stopped reading.
        timers.asyncAfter(deadline: .now() + 2) { [weak self] in self?.finish(.local(reason)) }
    }

    private func deliver(_ content: Data) throws(ProtocolError) {
        var raws: [RawMessage] = []
        var failure: ProtocolError?
        parser.withLockUnchecked { parser in
            parser.append(content)
            do throws(ProtocolError) {
                while let raw = try parser.next() { raws.append(raw) }
            } catch {
                failure = error
            }
        }
        // Decoding (JSON for control messages) runs outside every lock.
        var messages: [Message] = []
        for raw in raws {
            do throws(ProtocolError) {
                messages.append(try MessageCodec.decode(raw))
            } catch {
                failure = error
                break
            }
        }
        let handler = state.withLockUnchecked { state -> (@Sendable (Message) -> Void)? in
            state.statistics.bytesReceived += content.count
            state.statistics.messagesReceived += messages.count
            return state.onMessage
        }
        messages.forEach { handler?($0) }
        if let failure { throw failure }
    }

    private func finish(_ reason: CloseReason) {
        let (first, onClose) = state.withLockUnchecked { state -> (Bool, (@Sendable (CloseReason) -> Void)?) in
            guard !state.closed else { return (false, nil) }
            state.closed = true
            let handler = state.onClose
            state.onClose = nil
            state.onMessage = nil
            state.onReady = nil
            return (true, handler)
        }
        // Release the link on the first close even when nobody registered handlers.
        guard first else { return }
        Log.transport.info("connection.closed endpoint=\(self.endpointDescription, privacy: .public) reason=\(String(describing: reason), privacy: .public)")
        transport.cancel()
        onClose?(reason)
    }
}
