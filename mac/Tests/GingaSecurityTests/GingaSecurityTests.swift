import Foundation
import Security
import Testing
@testable import GingaSecurity

@Suite("DER")
struct DERTests {
    @Test func lengthsUseShortAndLongForms() {
        #expect(DER.length(5) == Data([0x05]))
        #expect(DER.length(127) == Data([0x7F]))
        #expect(DER.length(128) == Data([0x81, 0x80]))
        #expect(DER.length(300) == Data([0x82, 0x01, 0x2C]))
    }

    @Test func objectIdentifiersMatchTheStandardEncodings() {
        // ecdsa-with-SHA256 and prime256v1 as every X.509 library writes them.
        #expect(DER.objectIdentifier([1, 2, 840, 10045, 4, 3, 2]) == Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]))
        #expect(DER.objectIdentifier([1, 2, 840, 10045, 3, 1, 7]) == Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]))
        #expect(DER.objectIdentifier([2, 5, 4, 3]) == Data([0x06, 0x03, 0x55, 0x04, 0x03]))
    }

    @Test func integersAreMinimalAndPositive() {
        #expect(DER.integer(2) == Data([0x02, 0x01, 0x02]))
        #expect(DER.unsignedInteger(Data([0x00, 0x00, 0x7F])) == Data([0x02, 0x01, 0x7F]))
        #expect(DER.unsignedInteger(Data([0x80])) == Data([0x02, 0x02, 0x00, 0x80]))  // not negative
        #expect(DER.unsignedInteger(Data()) == Data([0x02, 0x01, 0x00]))
    }

    @Test func utcTimeIsZulu() {
        let date = Date(timeIntervalSince1970: 1_790_294_400)  // 2026-09-25T00:00:00Z
        #expect(DER.utcTime(date) == Data([0x17, 13]) + Data("260925000000Z".utf8))
    }
}

@Suite("SelfSignedCertificate")
struct SelfSignedCertificateTests {
    func makeKey() throws -> SecKey {
        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeySizeInBits: 256]
        return try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))  // in memory only
    }

    /// The Security framework itself must parse the certificate, find our key in it, and accept its
    /// signature when the certificate is its own anchor.
    @Test func securityFrameworkParsesAndTrustsItAsItsOwnAnchor() throws {
        let key = try makeKey()
        let der = try SelfSignedCertificate.make(privateKey: key, commonName: "Ginga on Test Mac")
        let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
        #expect(SecCertificateCopySubjectSummary(certificate) as String? == "Ginga on Test Mac")

        let embedded = try #require(SecCertificateCopyKey(certificate))
        let publicKey = try #require(SecKeyCopyPublicKey(key))
        #expect(SecKeyCopyExternalRepresentation(embedded, nil) as Data? == SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)

        var trust: SecTrust?
        #expect(SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust) == errSecSuccess)
        let evaluated = try #require(trust)
        SecTrustSetAnchorCertificates(evaluated, [certificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(evaluated, true)
        var error: CFError?
        #expect(SecTrustEvaluateWithError(evaluated, &error), "trust failed: \(String(describing: error))")
    }

    @Test func aTamperedCertificateIsNotTrusted() throws {
        var der = try SelfSignedCertificate.make(privateKey: try makeKey(), commonName: "Ginga")
        let index = der.index(der.startIndex, offsetBy: der.count / 2)
        der[index] ^= 0x01  // flip a bit inside the signed part
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return }  // unparsable is fine too
        var trust: SecTrust?
        SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust)
        let evaluated = try #require(trust)
        SecTrustSetAnchorCertificates(evaluated, [certificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(evaluated, true)
        #expect(!SecTrustEvaluateWithError(evaluated, nil))
    }

    @Test func validityNeverPassesUTCTimesLimit() throws {
        let late = Date(timeIntervalSince1970: 2_400_000_000)  // 2046: +20 years would be past 2049
        let der = try SelfSignedCertificate.make(privateKey: try makeKey(), commonName: "x", now: late)
        #expect(SecCertificateCreateWithData(nil, der as CFData) != nil)
        #expect(der.range(of: Data("491231235959Z".utf8)) != nil)
    }
}

@Suite("Pairing")
struct PairingTests {
    let mac = CertificateFingerprint(certificate: Data("mac certificate".utf8))
    let tablet = CertificateFingerprint(certificate: Data("tablet certificate".utf8))
    let macNonce = Data(repeating: 0x33, count: 32)
    let tabletNonce = Data(repeating: 0x44, count: 32)

    @Test func codeIsSixDigitsDeterministicAndOrderSensitive() {
        let code = PairingCode.code(mac: mac, tablet: tablet, macNonce: macNonce, tabletNonce: tabletNonce)
        #expect(code.count == 6 && code.allSatisfy(\.isNumber))
        #expect(PairingCode.code(mac: mac, tablet: tablet, macNonce: macNonce, tabletNonce: tabletNonce) == code)
        #expect(PairingCode.code(mac: tablet, tablet: mac, macNonce: macNonce, tabletNonce: tabletNonce) != code)
        #expect(PairingCode.code(mac: mac, tablet: tablet, macNonce: tabletNonce, tabletNonce: macNonce) != code)
    }

    @Test func aSubstitutedCertificateOrNonceChangesTheCode() {
        let attacker = CertificateFingerprint(certificate: Data("attacker certificate".utf8))
        let code = PairingCode.code(mac: mac, tablet: tablet, macNonce: macNonce, tabletNonce: tabletNonce)
        #expect(PairingCode.code(mac: attacker, tablet: tablet, macNonce: macNonce, tabletNonce: tabletNonce) != code)
        #expect(PairingCode.code(mac: mac, tablet: tablet, macNonce: Data(repeating: 0x35, count: 32), tabletNonce: tabletNonce) != code)
    }

    /// The commitment binds the tablet to its nonce before it sees the Mac's.
    @Test func theCommitmentBindsTheNonceAndBothCertificates() {
        let commitment = PairingCode.commitment(tablet: tablet, mac: mac, tabletNonce: tabletNonce)
        #expect(commitment.count == 32)
        #expect(PairingCode.commitment(tablet: tablet, mac: mac, tabletNonce: macNonce) != commitment)
        #expect(PairingCode.commitment(tablet: mac, mac: tablet, tabletNonce: tabletNonce) != commitment)
    }

    @Test func noncesAreFreshAndFullLength() {
        let nonce = PairingCode.makeNonce()
        #expect(nonce.count == PairingCode.nonceLength)
        #expect(PairingCode.makeNonce() != nonce)
    }

    @Test func fingerprintsRoundTripThroughHex() {
        #expect(mac.hex.count == 64)
        #expect(CertificateFingerprint(hex: mac.hex) == mac)
        #expect(CertificateFingerprint(hex: "zz") == nil)
        #expect(CertificateFingerprint(hex: "+1" + String(mac.hex.dropFirst(2))) == nil)  // no signs
    }

    @Test func hexIsStrict() {
        #expect(Hex.decode("00ff7A") == Data([0x00, 0xff, 0x7a]))
        #expect(Hex.decode("") == Data())
        #expect(Hex.decode("abc") == nil)
        #expect(Hex.decode("+f") == nil)
        #expect(Hex.decode("0x") == nil)
        #expect(Hex.encode(Data([0x00, 0xab])) == "00ab")
    }

    /// Shared with the Kotlin implementation (PROTOCOL.md §6): both must derive the same values.
    @Test func knownVector() {
        let a = CertificateFingerprint(hex: String(repeating: "11", count: 32))!
        let b = CertificateFingerprint(hex: String(repeating: "22", count: 32))!
        #expect(Hex.encode(PairingCode.commitment(tablet: b, mac: a, tabletNonce: tabletNonce)) == PairingCodeVector.commitment)
        #expect(PairingCode.code(mac: a, tablet: b, macNonce: macNonce, tabletNonce: tabletNonce) == PairingCodeVector.code)
    }
}

/// Fingerprints of 32 × 0x11 (Mac) and 32 × 0x22 (tablet), nonces of 32 × 0x33 (Mac) and
/// 32 × 0x44 (tablet). Written once from this implementation; the Android suite asserts the same.
enum PairingCodeVector {
    static let commitment = "052c957131b84f9b12e9519024c730dbf4fa95abac4b8d2e5b1118b2cef8ec89"
    static let code = "053656"
}

@Suite("LoopbackToken")
struct LoopbackTokenTests {
    @Test func tokensAreFreshHexAndCompareExactly() {
        let token = LoopbackToken.generate()
        #expect(token.count == 64 && Hex.decode(token)?.count == 32)
        #expect(LoopbackToken.generate() != token)
        #expect(LoopbackToken.matches(token, expected: token))
        #expect(!LoopbackToken.matches(nil, expected: token))
        #expect(!LoopbackToken.matches(String(token.dropLast()), expected: token))
        #expect(!LoopbackToken.matches(String(token.dropLast()) + "x", expected: token))
    }
}

/// A file-based keychain in a temporary directory, like the login keychain, deleted afterwards.
final class TemporaryKeychain {
    let keychain: SecKeychain
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ginga-keychain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let password = UUID().uuidString
        var created: SecKeychain?
        let status = SecKeychainCreate(directory.appendingPathComponent("test.keychain-db").path, UInt32(password.utf8.count), password, false, nil, &created)
        keychain = try #require(created, "SecKeychainCreate failed: \(status)")
    }

    deinit {
        SecKeychainDelete(keychain)
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite("KeychainPinStore", .serialized)
struct KeychainPinStoreTests {
    let a = CertificateFingerprint(certificate: Data("tablet a".utf8))
    let b = CertificateFingerprint(certificate: Data("tablet b".utf8))

    /// The control panel lists paired tablets from `all`: it must work on a file-based keychain.
    @Test func pinsAreListedFoundAndForgotten() throws {
        let temporary = try TemporaryKeychain()
        let store = KeychainPinStore(keychain: temporary.keychain)
        #expect(store.all.isEmpty)
        try store.add(PairedTablet(fingerprint: a, name: "Tab A"))
        try store.add(PairedTablet(fingerprint: b, name: "Tab B"))
        #expect(Set(store.all.map(\.name)) == ["Tab A", "Tab B"])
        #expect(store.tablet(for: a)?.name == "Tab A")
        try store.add(PairedTablet(fingerprint: a, name: "Tab A renamed"))  // replaces
        #expect(store.all.count == 2)
        try store.remove(a)
        #expect(store.all.map(\.name) == ["Tab B"])
        #expect(store.tablet(for: a) == nil)
        try store.remove(a)  // already gone: fine
    }
}

@Suite("TLSIdentityStore", .serialized)
struct TLSIdentityStoreTests {
    /// Tablets pin this certificate: the Mac must present the same one on every launch.
    @Test func theIdentityIsCreatedOnceAndLoadedAfterwards() throws {
        let temporary = try TemporaryKeychain()
        #expect(try TLSIdentityStore.load(keychain: temporary.keychain) == nil)
        let created = try TLSIdentityStore.loadOrCreate(commonName: "Ginga on Test Mac", keychain: temporary.keychain)
        let loaded = try TLSIdentityStore.loadOrCreate(commonName: "Ginga on Renamed Mac", keychain: temporary.keychain)
        #expect(loaded.fingerprint == created.fingerprint)
        #expect(try TLSIdentityStore.load(keychain: temporary.keychain)?.fingerprint == created.fingerprint)
    }

    /// Several identities (left by earlier builds): always the oldest, so the choice is stable.
    @Test func withSeveralTheOldestWins() throws {
        let temporary = try TemporaryKeychain()
        let first = try TLSIdentityStore.create(commonName: "Ginga first", keychain: temporary.keychain)
        Thread.sleep(forTimeInterval: 1.1)  // keychain creation dates have 1 s resolution
        _ = try TLSIdentityStore.create(commonName: "Ginga second", keychain: temporary.keychain)
        #expect(try TLSIdentityStore.load(keychain: temporary.keychain)?.fingerprint == first.fingerprint)
    }
}

@Suite("DirectLinkCrypto")
struct DirectLinkCryptoTests {
    let key = Data(repeating: 0x55, count: 32)
    let keyId = Data([1, 2, 3, 4, 5, 6, 7, 8])
    let nonce = Data(repeating: 0x09, count: 12)
    let credentials = #"{"expires":1790000000,"psk":"gn-Example-Passphrase","session":"00112233445566778899aabbccddeeff","ssid":"DIRECT-Ginga-0102"}"#

    /// PROTOCOL.md §6b vectors, shared with the Android suite.
    @Test func matchesTheProtocolVectors() throws {
        #expect(DirectLinkCrypto.subkey(key, for: .credentials).withUnsafeBytes { Hex.encode(Data($0)) }
                == "75bc03cb45573842d8a842de4be2e8af48b937dd59f5d8fa3a8f4894b0a94aee")
        let sealed = try DirectLinkCrypto.seal(Data(credentials.utf8), key: key, keyId: keyId, purpose: .credentials, nonce: nonce)
        #expect(Hex.encode(sealed) == "01020304050607080909090909090909090909099f2fa452568ca28a265f8f20a285763f7681dcb148c12a085ae117d046ae61bcb27831e6ebea98d66170f2e14d9ced2dbf867fa7668ca1cbb75dc180323f700b276345f79d8e5fcfbe22eacba5221bf34d743879225aeb1e6022a12b24f2753566f99f9413d38173182cc6c39505376f99ae5c66985a096006fdff5857755fb50029c8a9e706f8f0c9da5beb")
        let address = #"{"host":"192.168.49.23","port":55471,"session":"00112233445566778899aabbccddeeff"}"#
        let sealedAddress = try DirectLinkCrypto.seal(Data(address.utf8), key: key, keyId: keyId, purpose: .address, nonce: nonce)
        #expect(Hex.encode(sealedAddress).hasSuffix("4a1f956830bb6bfcddbbb3051fe54a47db3099df512b1dc54407012e375f7edd330268bac91be8335a2c4959b014548f3eebeb781cd44faf"))
    }

    @Test func opensWhatItSealsAndRejectsTampering() throws {
        let sealed = try DirectLinkCrypto.seal(Data(credentials.utf8), key: key, keyId: keyId, purpose: .credentials)
        #expect(DirectLinkCrypto.keyId(of: sealed) == keyId)
        #expect(try DirectLinkCrypto.open(sealed, key: key, purpose: .credentials) == Data(credentials.utf8))
        #expect(throws: DirectLinkCrypto.Failure.authentication) { try DirectLinkCrypto.open(sealed, key: key, purpose: .address) }  // other direction's key
        var tampered = sealed
        tampered[20] ^= 1
        #expect(throws: DirectLinkCrypto.Failure.authentication) { try DirectLinkCrypto.open(tampered, key: key, purpose: .credentials) }
        var otherId = sealed
        otherId[0] ^= 1  // the key id is authenticated too
        #expect(throws: DirectLinkCrypto.Failure.authentication) { try DirectLinkCrypto.open(otherId, key: key, purpose: .credentials) }
        #expect(throws: DirectLinkCrypto.Failure.tooShort) { try DirectLinkCrypto.open(Data([1, 2, 3]), key: key, purpose: .credentials) }
    }

    @Test func keysAreStoredPerTabletAndFoundById() throws {
        let temporary = try TemporaryKeychain()
        let store = KeychainDirectKeyStore(keychain: temporary.keychain)
        let created = try store.keyCreatingIfNeeded(deviceId: "tab-a", name: "Tab S11")
        #expect(created.key.count == 32 && created.keyId.count == 8)
        #expect(try store.keyCreatingIfNeeded(deviceId: "tab-a", name: "Tab S11") == created)  // stable
        #expect(store.key(forId: created.keyId) == created)
        #expect(store.key(forId: Data(repeating: 0, count: 8)) == nil)
    }
}
