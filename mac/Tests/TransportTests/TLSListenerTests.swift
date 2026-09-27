import Foundation
import Security
import GingaProtocol
import GingaSecurity
import Testing
@testable import Transport

/// An identity in a throwaway keychain file, so tests never touch the user's login keychain.
final class ThrowawayIdentity {
    let identity: SecIdentity
    let certificate: Data
    private let keychain: SecKeychain

    init(commonName: String) throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("ginga-test-\(UUID().uuidString).keychain-db").path
        let password = "ginga-test"
        var created: SecKeychain?
        let status = SecKeychainCreate(path, UInt32(password.utf8.count), password, false, nil, &created)
        keychain = try #require(created, "SecKeychainCreate failed: \(status)")
        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeySizeInBits: 256,
            kSecAttrIsPermanent: true, kSecUseKeychain: keychain, kSecAttrLabel: commonName,
        ]
        let key = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error), "key: \(String(describing: error?.takeRetainedValue()))")
        certificate = try SelfSignedCertificate.make(privateKey: key, commonName: commonName)
        let secCertificate = try #require(SecCertificateCreateWithData(nil, certificate as CFData))
        let added = SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: secCertificate, kSecUseKeychain: keychain] as CFDictionary, nil)
        #expect(added == errSecSuccess)
        var identity: SecIdentity?
        let identityStatus = SecIdentityCreateWithCertificate(keychain, secCertificate, &identity)
        self.identity = try #require(identity, "identity: \(identityStatus)")
    }

    deinit {
        SecKeychainDelete(keychain)
    }
}

final class Box<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    func set(_ value: T) { lock.withLock { stored = value } }
    var value: T? { lock.withLock { stored } }
}

func waitUntil(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@Suite("TLS listener", .serialized)
struct TLSListenerTests {
    /// Mutual TLS 1.3 with self-signed identities: each side can read the other's certificate
    /// (what pairing pins), and messages flow.
    @Test func mutualTLSExchangesCertificatesAndMessages() async throws {
        let mac = try ThrowawayIdentity(commonName: "Ginga test Mac")
        let tablet = try ThrowawayIdentity(commonName: "Ginga test tablet")
        let listener = try TLSListener(identity: mac.identity, advertisement: nil, loopbackOnly: true)
        let port = Box<UInt16>()
        let accepted = Box<NetworkByteTransport>()
        let serverConnection = Box<MessageConnection>()  // the stream session would own it
        let received = Box<Message>()
        listener.start { event in
            switch event {
            case .ready(let bound): port.set(bound)
            case .connection(let connection, let transport):
                accepted.set(transport)
                serverConnection.set(connection)
                connection.setHandlers(onMessage: { received.set($0) }, onClose: { _ in })
                connection.start()
            case .failed: break
            }
        }
        defer { listener.stop() }
        #expect(await waitUntil { port.value != nil })

        let (client, clientTransport) = TLSListener.connect(host: "127.0.0.1", port: try #require(port.value), identity: tablet.identity)
        let ready = Box<Bool>()
        client.setHandlers(onReady: { ready.set(true) }, onMessage: { _ in }, onClose: { _ in })
        client.start()
        #expect(await waitUntil { ready.value == true })
        client.send(.keyframeRequest(KeyframeRequest(reason: "startup", lastDecodedFrameId: nil)))

        #expect(await waitUntil { received.value != nil })
        #expect(received.value == .keyframeRequest(KeyframeRequest(reason: "startup", lastDecodedFrameId: nil)))
        #expect(accepted.value?.peerCertificate() == tablet.certificate)
        #expect(clientTransport.peerCertificate() == mac.certificate)
        client.close(reason: "done")
    }
}
