import CryptoKit
import Foundation
import Security

/// The no-router mode's handover crypto (PROTOCOL.md §6b): the tablet's network credentials and
/// the Mac's address travel over Bluetooth LE sealed with a key both sides got over an
/// authenticated session.
///
/// Value layout: `keyId (8) ‖ nonce (12) ‖ AES-256-GCM ciphertext ‖ tag (16)`, AAD = keyId,
/// subkey = HKDF-SHA256(key, salt "ginga-direct-v1", info "credentials" | "address").
public enum DirectLinkCrypto {
    public enum Purpose: String, Sendable { case credentials, address }

    public enum Failure: Error, Equatable, Sendable {
        case tooShort
        case unknownKey
        case authentication
    }

    public static let keyIdLength = 8

    public static func subkey(_ key: Data, for purpose: Purpose) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: key), salt: Data("ginga-direct-v1".utf8),
            info: Data(purpose.rawValue.utf8), outputByteCount: 32
        )
    }

    public static func seal(_ plaintext: Data, key: Data, keyId: Data, purpose: Purpose, nonce: Data? = nil) throws -> Data {
        let gcmNonce = try nonce.map { try AES.GCM.Nonce(data: $0) } ?? AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: subkey(key, for: purpose), nonce: gcmNonce, authenticating: keyId)
        guard let combined = sealed.combined else { throw Failure.authentication }
        return keyId + combined
    }

    /// The key id a value was sealed with (to pick the key).
    public static func keyId(of value: Data) -> Data? {
        value.count > keyIdLength ? Data(value.prefix(keyIdLength)) : nil
    }

    public static func open(_ value: Data, key: Data, purpose: Purpose) throws(Failure) -> Data {
        guard value.count > keyIdLength + 12 + 16 else { throw .tooShort }
        let keyId = Data(value.prefix(keyIdLength))
        do {
            let box = try AES.GCM.SealedBox(combined: Data(value.dropFirst(keyIdLength)))
            return try AES.GCM.open(box, using: subkey(key, for: purpose), authenticating: keyId)
        } catch {
            throw .authentication
        }
    }
}

/// One tablet's direct-link key.
public struct DirectKey: Codable, Hashable, Sendable {
    public var keyId: Data
    public var key: Data
    /// HELLO `device.id` of the tablet it belongs to.
    public var deviceId: String
    public var name: String

    public init(keyId: Data, key: Data, deviceId: String, name: String) {
        self.keyId = keyId
        self.key = key
        self.deviceId = deviceId
        self.name = name
    }

    public static func generate(deviceId: String, name: String) -> DirectKey {
        DirectKey(keyId: Data(PairingCode.makeNonce().prefix(8)), key: PairingCode.makeNonce(), deviceId: deviceId, name: name)
    }
}

public protocol DirectKeyStore: AnyObject, Sendable {
    func key(forDevice deviceId: String) -> DirectKey?
    func key(forId keyId: Data) -> DirectKey?
    func save(_ key: DirectKey) throws
}

extension DirectKeyStore {
    /// The tablet's key, created on first use.
    public func keyCreatingIfNeeded(deviceId: String, name: String) throws -> DirectKey {
        if let existing = key(forDevice: deviceId) { return existing }
        let created = DirectKey.generate(deviceId: deviceId, name: name)
        try save(created)
        return created
    }
}

/// Direct-link keys as generic-password items in the login keychain (account = device id).
public final class KeychainDirectKeyStore: DirectKeyStore, @unchecked Sendable {  // the keychain is thread-safe
    public static let service = "dev.ginga.direct-link"
    private let keychain: CFTypeRef?

    public init(keychain: CFTypeRef? = nil) {
        self.keychain = keychain
    }

    private func query(_ attributes: [CFString: Any]) -> CFDictionary {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service]
        query.merge(attributes) { _, new in new }
        if let keychain { query[kSecMatchSearchList] = [keychain] }
        return query as CFDictionary
    }

    public func key(forDevice deviceId: String) -> DirectKey? {
        var data: CFTypeRef?
        guard SecItemCopyMatching(query([kSecAttrAccount: deviceId, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]), &data) == errSecSuccess,
              let data = data as? Data else { return nil }
        return try? JSONDecoder().decode(DirectKey.self, from: data)
    }

    public func key(forId keyId: Data) -> DirectKey? {
        var items: CFTypeRef?
        guard SecItemCopyMatching(query([kSecReturnAttributes: true, kSecMatchLimit: kSecMatchLimitAll]), &items) == errSecSuccess,
              let attributes = items as? [[String: Any]] else { return nil }
        return attributes.lazy
            .compactMap { $0[kSecAttrAccount as String] as? String }
            .compactMap(key(forDevice:))
            .first { $0.keyId == keyId }
    }

    public func save(_ key: DirectKey) throws {
        let data = try JSONEncoder().encode(key)
        SecItemDelete(query([kSecAttrAccount: key.deviceId]))
        var item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: key.deviceId,
            kSecAttrLabel: "Ginga direct link: \(key.name)", kSecValueData: data,
        ]
        if let keychain { item[kSecUseKeychain] = keychain }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecurityError.keychain(status, "add direct-link key") }
    }
}

public final class MemoryDirectKeyStore: DirectKeyStore, @unchecked Sendable {  // guarded by `lock`
    private let lock = NSLock()
    private var keys: [String: DirectKey] = [:]

    public init(_ keys: [DirectKey] = []) {
        keys.forEach { self.keys[$0.deviceId] = $0 }
    }

    public func key(forDevice deviceId: String) -> DirectKey? { lock.withLock { keys[deviceId] } }
    public func key(forId keyId: Data) -> DirectKey? { lock.withLock { keys.values.first { $0.keyId == keyId } } }
    public func save(_ key: DirectKey) throws { lock.withLock { keys[key.deviceId] = key } }
}
