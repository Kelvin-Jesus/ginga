import Foundation
import Network
import os
import Security
import GingaProtocol

/// The Wi‑Fi listener (M7): TLS 1.3 with this Mac's identity, a client certificate required from
/// every tablet, advertised over Bonjour. Certificates aren't validated against a chain: the
/// stream session pins fingerprints (pairing), so any certificate passes the handshake here.
public final class TLSListener: @unchecked Sendable {  // NWListener is thread-safe; `listener` is set once
    public enum Event: Sendable {
        case ready(port: UInt16)
        case failed(String)
        /// A tablet connected; `transport.peerCertificate()` is its certificate once ready.
        case connection(MessageConnection, transport: NetworkByteTransport)
    }

    public struct Advertisement: Sendable {
        public var name: String
        public var type: String
        public var txt: [String: String]

        public init(name: String, type: String = "_ginga._tcp", txt: [String: String]) {
            self.name = name
            self.type = type
            self.txt = txt
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.ginga.transport.tls-listener", qos: .userInitiated)

    /// `loopbackOnly` is for tests (no LAN exposure, no firewall prompt).
    public init(identity: SecIdentity, port: UInt16 = 0, advertisement: Advertisement?, loopbackOnly: Bool = false) throws {
        let parameters = NWParameters(tls: Self.serverTLS(identity: identity, queue: queue), tcp: Self.tcpOptions())
        parameters.includePeerToPeer = false  // Android has no AWDL
        let nwPort = port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: port)!
        if loopbackOnly {
            parameters.requiredInterfaceType = .loopback
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        }
        listener = try NWListener(using: parameters, on: nwPort)
        if let advertisement {
            listener.service = NWListener.Service(name: advertisement.name, type: advertisement.type, domain: nil, txtRecord: NWTXTRecord(advertisement.txt))
        }
    }

    public func start(_ handler: @escaping @Sendable (Event) -> Void) {
        listener.stateUpdateHandler = { [listener] state in
            switch state {
            case .ready:
                handler(.ready(port: listener.port?.rawValue ?? 0))
            case .failed(let error):
                handler(.failed(String(describing: error)))
            default:
                break
            }
        }
        listener.newConnectionHandler = { connection in
            let transport = NetworkByteTransport(connection: connection)
            handler(.connection(MessageConnection(transport: transport), transport: transport))
        }
        listener.start(queue: queue)
    }

    public func stop() {
        listener.cancel()
    }

    static func tcpOptions() -> NWProtocolTCP.Options {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        return tcp
    }

    static func serverTLS(identity: SecIdentity, queue: DispatchQueue) -> NWProtocolTLS.Options {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        if let local = sec_identity_create(identity) { sec_protocol_options_set_local_identity(options, local) }
        sec_protocol_options_set_peer_authentication_required(options, true)
        sec_protocol_options_set_verify_block(options, { _, _, complete in complete(true) }, queue)
        return tls
    }

    /// A TLS client (tests and `ginga receive --tls`): presents `identity`, accepts any server
    /// certificate (the caller pins it via `peerCertificate()`).
    public static func connect(host: String, port: UInt16, identity: SecIdentity) -> (MessageConnection, NetworkByteTransport) {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        if let local = sec_identity_create(identity) { sec_protocol_options_set_local_identity(options, local) }
        sec_protocol_options_set_verify_block(options, { _, _, complete in complete(true) }, DispatchQueue.global())
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: NWParameters(tls: tls, tcp: tcpOptions()))
        let transport = NetworkByteTransport(connection: connection)
        return (MessageConnection(transport: transport), transport)
    }
}
