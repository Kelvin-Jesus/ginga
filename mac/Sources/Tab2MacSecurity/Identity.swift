import Foundation
import os
import Security
import Tab2MacCore

extension Log {
    public static let security = Logger(subsystem: subsystem, category: "security")
}

/// This Mac's TLS identity for Wi‑Fi (M7): a P-256 key and a self-signed certificate that
/// tablets pin at pairing.
public struct TLSIdentity: @unchecked Sendable {  // SecIdentity is immutable and thread-safe
    public let identity: SecIdentity
    public let certificate: Data

    public var fingerprint: CertificateFingerprint { CertificateFingerprint(certificate: certificate) }
}

/// Creates the identity once in the login keychain and loads it afterwards. Items the app
/// creates list the app in their access control, so reading them back never prompts (with a
/// stable code signature, see docs/development.md).
///
/// The label is on the private key: the keychain labels certificates with their subject and
/// ignores a label given when adding one. The certificate is found from the key through the
/// public-key hash both carry.
public enum TLSIdentityStore {
    public static let label = "Tab2Mac Wi-Fi identity"

    /// - Parameter keychain: a specific file-based keychain (tests); nil uses the login keychain.
    public static func loadOrCreate(commonName: String, keychain: CFTypeRef? = nil) throws -> TLSIdentity {
        if let existing = try load(keychain: keychain) { return existing }
        return try create(commonName: commonName, keychain: keychain)
    }

    /// The oldest complete identity, so the choice never changes once made (earlier builds could
    /// leave several behind).
    public static func load(keychain: CFTypeRef? = nil) throws -> TLSIdentity? {
        var keysQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrLabel: label,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll,
        ]
        if let keychain { keysQuery[kSecMatchSearchList] = [keychain] }
        var items: CFTypeRef?
        let status = SecItemCopyMatching(keysQuery as CFDictionary, &items)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let keys = items as? [[String: Any]] else { throw SecurityError.keychain(status, "find keys") }

        let candidates = keys.sorted {
            ($0[kSecAttrCreationDate as String] as? Date ?? .distantFuture) < ($1[kSecAttrCreationDate as String] as? Date ?? .distantFuture)
        }
        for key in candidates {
            guard let hash = key[kSecAttrApplicationLabel as String] as? Data else { continue }
            var certificateQuery: [CFString: Any] = [
                kSecClass: kSecClassCertificate,
                kSecAttrPublicKeyHash: hash,
                kSecReturnRef: true,
                kSecMatchLimit: kSecMatchLimitOne,
            ]
            if let keychain { certificateQuery[kSecMatchSearchList] = [keychain] }
            var item: CFTypeRef?
            guard SecItemCopyMatching(certificateQuery as CFDictionary, &item) == errSecSuccess, let item,
                  CFGetTypeID(item) == SecCertificateGetTypeID() else { continue }
            let certificate = item as! SecCertificate  // swiftlint:disable:this force_cast — type checked above
            var identity: SecIdentity?
            guard SecIdentityCreateWithCertificate(keychain, certificate, &identity) == errSecSuccess, let identity else { continue }
            return TLSIdentity(identity: identity, certificate: SecCertificateCopyData(certificate) as Data)
        }
        Log.security.error("security.identity-incomplete keys=\(keys.count)")
        return nil  // keys without their certificate: make a new identity
    }

    static func create(commonName: String, keychain: CFTypeRef? = nil) throws -> TLSIdentity {
        var error: Unmanaged<CFError>?
        var attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrLabel: label,
            kSecAttrIsPermanent: true,
        ]
        if let keychain { attributes[kSecUseKeychain] = keychain }
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw SecurityError.keyGeneration(error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown")
        }
        let der = try SelfSignedCertificate.make(privateKey: key, commonName: commonName)
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { throw SecurityError.invalidCertificate }
        var add: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValueRef: certificate]
        if let keychain { add[kSecUseKeychain] = keychain }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw SecurityError.keychain(status, "add certificate") }
        var identity: SecIdentity?
        let identityStatus = SecIdentityCreateWithCertificate(keychain, certificate, &identity)
        guard identityStatus == errSecSuccess, let identity else { throw SecurityError.keychain(identityStatus, "create identity") }
        Log.security.info("security.identity-created fingerprint=\(CertificateFingerprint(certificate: der).hex, privacy: .public)")
        return TLSIdentity(identity: identity, certificate: der)
    }
}

/// A tablet that completed pairing.
public struct PairedTablet: Codable, Hashable, Sendable {
    public var fingerprint: CertificateFingerprint
    public var name: String
    public var pairedAt: Date

    public init(fingerprint: CertificateFingerprint, name: String, pairedAt: Date = Date()) {
        self.fingerprint = fingerprint
        self.name = name
        self.pairedAt = pairedAt
    }
}

/// Pinned tablet certificates.
public protocol PinStore: AnyObject, Sendable {
    func tablet(for fingerprint: CertificateFingerprint) -> PairedTablet?
    func add(_ tablet: PairedTablet) throws
    func remove(_ fingerprint: CertificateFingerprint) throws
    var all: [PairedTablet] { get }
}

/// Pins as generic-password items in the login keychain (one per tablet, account = fingerprint).
public final class KeychainPinStore: PinStore, @unchecked Sendable {  // the keychain is thread-safe
    public static let service = "dev.tab2mac.paired-tablet"
    /// A specific file-based keychain (tests); nil uses the default (login) keychain.
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

    public func tablet(for fingerprint: CertificateFingerprint) -> PairedTablet? {
        var data: CFTypeRef?
        let lookup = query([kSecAttrAccount: fingerprint.hex, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne])
        guard SecItemCopyMatching(lookup, &data) == errSecSuccess, let data = data as? Data else { return nil }
        return try? JSONDecoder().decode(PairedTablet.self, from: data)
    }

    public func add(_ tablet: PairedTablet) throws {
        let data = try JSONEncoder().encode(tablet)
        try? remove(tablet.fingerprint)
        var item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: tablet.fingerprint.hex,
            kSecAttrLabel: "Tab2Mac paired tablet: \(tablet.name)", kSecValueData: data,
        ]
        if let keychain { item[kSecUseKeychain] = keychain }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecurityError.keychain(status, "add pin") }
    }

    public func remove(_ fingerprint: CertificateFingerprint) throws {
        let status = SecItemDelete(query([kSecAttrAccount: fingerprint.hex]))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecurityError.keychain(status, "remove pin") }
    }

    /// Lists attributes first, then reads each item: the file-based (login) keychain refuses
    /// `kSecReturnData` together with `kSecMatchLimitAll`.
    public var all: [PairedTablet] {
        var items: CFTypeRef?
        let list = query([kSecReturnAttributes: true, kSecMatchLimit: kSecMatchLimitAll])
        guard SecItemCopyMatching(list, &items) == errSecSuccess, let attributes = items as? [[String: Any]] else { return [] }
        return attributes
            .compactMap { ($0[kSecAttrAccount as String] as? String).flatMap(CertificateFingerprint.init(hex:)) }
            .compactMap(tablet(for:))
    }
}

/// For tests and previews.
public final class MemoryPinStore: PinStore, @unchecked Sendable {  // guarded by `lock`
    private let lock = NSLock()
    private var tablets: [CertificateFingerprint: PairedTablet] = [:]

    public init(_ tablets: [PairedTablet] = []) {
        tablets.forEach { self.tablets[$0.fingerprint] = $0 }
    }

    public func tablet(for fingerprint: CertificateFingerprint) -> PairedTablet? { lock.withLock { tablets[fingerprint] } }
    public func add(_ tablet: PairedTablet) throws { lock.withLock { tablets[tablet.fingerprint] = tablet } }
    public func remove(_ fingerprint: CertificateFingerprint) throws { _ = lock.withLock { tablets.removeValue(forKey: fingerprint) } }
    public var all: [PairedTablet] { lock.withLock { Array(tablets.values) } }
}
