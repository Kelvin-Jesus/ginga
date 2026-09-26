import Foundation
import Network
import os
import Tab2MacCore

/// Accepts receiver connections on TCP. Loopback-only by default: over USB the tablet reaches
/// it through `adb reverse`, and the unencrypted stream is never exposed on the LAN (Wi‑Fi
/// arrives with TLS pairing in M7).
public final class TCPServer: @unchecked Sendable {  // NWListener is thread-safe; nothing else is mutable
    public enum Event: Sendable {
        case listening(port: UInt16)
        case failed(String)
        case connection(MessageConnection)
    }

    public static let defaultPort: UInt16 = 47800

    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.tab2mac.transport.server", qos: .userInitiated)

    /// - Parameter port: 0 picks a free port (tests).
    public init(port: UInt16 = TCPServer.defaultPort, loopbackOnly: Bool = true) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        let nwPort = port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: port)!
        if loopbackOnly {
            parameters.requiredInterfaceType = .loopback
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
            listener = try NWListener(using: parameters)
        } else {
            listener = try NWListener(using: parameters, on: nwPort)
        }
    }

    public func start(_ handler: @escaping @Sendable (Event) -> Void) {
        listener.stateUpdateHandler = { [listener] state in
            switch state {
            case .ready:
                let port = listener.port?.rawValue ?? 0
                Log.transport.info("server.listening port=\(port)")
                handler(.listening(port: port))
            case .failed(let error):
                Log.transport.error("server.failed reason=\(String(describing: error), privacy: .public)")
                handler(.failed(String(describing: error)))
            default:
                break
            }
        }
        listener.newConnectionHandler = { connection in
            Log.transport.info("server.accepted endpoint=\(String(describing: connection.endpoint), privacy: .public)")
            handler(.connection(MessageConnection(connection: connection)))
        }
        listener.start(queue: queue)
    }

    public func stop() {
        listener.cancel()
    }
}
