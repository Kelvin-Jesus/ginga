import CryptoKit
import Foundation
import Security

/// Minimal DER (X.690) encoding: just what a self-signed X.509 certificate needs.
enum DER {
    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        Data([tag]) + length(content.count) + content
    }

    static func length(_ count: Int) -> Data {
        guard count >= 0x80 else { return Data([UInt8(count)]) }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func sequence(_ parts: [Data]) -> Data { tlv(0x30, parts.reduce(Data(), +)) }
    static func set(_ parts: [Data]) -> Data { tlv(0x31, parts.reduce(Data(), +)) }
    static func explicit(_ tagNumber: UInt8, _ content: Data) -> Data { tlv(0xA0 | tagNumber, content) }
    static func utf8String(_ string: String) -> Data { tlv(0x0C, Data(string.utf8)) }
    /// No unused bits.
    static func bitString(_ bytes: Data) -> Data { tlv(0x03, Data([0]) + bytes) }

    /// A non-negative INTEGER from big-endian bytes.
    static func unsignedInteger(_ bytes: Data) -> Data {
        var content = Data(bytes.drop { $0 == 0 })
        if content.isEmpty { content = Data([0]) }
        if content[content.startIndex] & 0x80 != 0 { content.insert(0, at: content.startIndex) }
        return tlv(0x02, content)
    }

    static func integer(_ value: UInt64) -> Data {
        unsignedInteger(withUnsafeBytes(of: value.bigEndian) { Data($0) })
    }

    static func objectIdentifier(_ components: [UInt]) -> Data {
        precondition(components.count >= 2)
        var content = Data([UInt8(components[0] * 40 + components[1])])
        for component in components.dropFirst(2) {
            var chunk = [UInt8(component & 0x7F)]
            var value = component >> 7
            while value > 0 {
                chunk.insert(UInt8(value & 0x7F) | 0x80, at: 0)
                value >>= 7
            }
            content.append(contentsOf: chunk)
        }
        return tlv(0x06, content)
    }

    /// UTCTime (YYMMDDHHMMSSZ): RFC 5280 requires it for dates through 2049.
    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Data(formatter.string(from: date).utf8))
    }
}

public enum SecurityError: Error, CustomStringConvertible {
    case keyGeneration(String)
    case signing(String)
    case keychain(OSStatus, String)
    case invalidCertificate

    public var description: String {
        switch self {
        case .keyGeneration(let reason): "key generation failed: \(reason)"
        case .signing(let reason): "signing failed: \(reason)"
        case .keychain(let status, let operation): "keychain \(operation) failed: \(status)"
        case .invalidCertificate: "the certificate could not be parsed"
        }
    }
}

/// A self-signed X.509 v3 certificate for a P-256 key (ECDSA with SHA-256). macOS has no public
/// API that creates certificates; TLS on Wi‑Fi (M7) needs one per device, pinned at pairing.
public enum SelfSignedCertificate {
    static let ecdsaWithSHA256: [UInt] = [1, 2, 840, 10045, 4, 3, 2]
    static let ecPublicKey: [UInt] = [1, 2, 840, 10045, 2, 1]
    static let prime256v1: [UInt] = [1, 2, 840, 10045, 3, 1, 7]
    static let commonNameAttribute: [UInt] = [2, 5, 4, 3]
    /// The last instant UTCTime can express.
    static let latestNotAfter = Date(timeIntervalSince1970: 2_524_607_999)  // 2049-12-31T23:59:59Z

    public static func make(privateKey: SecKey, commonName: String, now: Date = Date(), serialNumber: Data? = nil) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let point = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw SecurityError.keyGeneration("no exportable public key")
        }
        let algorithm = DER.sequence([DER.objectIdentifier(ecdsaWithSHA256)])
        let name = DER.sequence([DER.set([DER.sequence([DER.objectIdentifier(commonNameAttribute), DER.utf8String(commonName)])])])
        let notAfter = min(now.addingTimeInterval(20 * 365 * 86_400), latestNotAfter)
        let validity = DER.sequence([DER.utcTime(now.addingTimeInterval(-86_400)), DER.utcTime(notAfter)])
        let subjectPublicKeyInfo = DER.sequence([
            DER.sequence([DER.objectIdentifier(ecPublicKey), DER.objectIdentifier(prime256v1)]),
            DER.bitString(point),
        ])
        let serial = serialNumber ?? Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let tbsCertificate = DER.sequence([
            DER.explicit(0, DER.integer(2)),  // v3
            DER.unsignedInteger(serial),
            algorithm,
            name,  // issuer = subject: self-signed
            validity,
            name,
            subjectPublicKeyInfo,
        ])
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, tbsCertificate as CFData, &error) as Data? else {
            throw SecurityError.signing(error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown")
        }
        return DER.sequence([tbsCertificate, algorithm, DER.bitString(signature)])
    }
}

/// SHA-256 of a certificate's DER: what pairing pins.
public struct CertificateFingerprint: Hashable, Sendable, Codable, CustomStringConvertible {
    public let bytes: Data

    public init(certificate der: Data) {
        bytes = Data(SHA256.hash(data: der))
    }

    public init?(hex: String) {
        guard let data = Hex.decode(hex), data.count == 32 else { return nil }
        bytes = data
    }

    public var hex: String { Hex.encode(bytes) }
    public var description: String { hex }
}

/// Numeric comparison with a commitment (PROTOCOL.md §6), as in Bluetooth LE Secure Connections.
///
/// The code covers both certificates and a fresh nonce from each side. The tablet commits to its
/// nonce before it learns the Mac's, and reveals it only afterwards, so neither side (nor a man in
/// the middle, who must commit toward the Mac before any nonce is known) can steer the code: an
/// attacker gets one guess at a 6-digit code per attempt, instead of searching offline for
/// certificates that make both screens show the same digits.
public enum PairingCode {
    public static let nonceLength = 32

    /// A fresh random nonce for one pairing attempt.
    public static func makeNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: nonceLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes)
    }

    /// What the tablet sends before it learns the Mac's nonce: SHA-256(tabletFP ‖ macFP ‖ tabletNonce).
    public static func commitment(tablet: CertificateFingerprint, mac: CertificateFingerprint, tabletNonce: Data) -> Data {
        Data(SHA256.hash(data: tablet.bytes + mac.bytes + tabletNonce))
    }

    /// The code both screens show: the first 4 bytes of SHA-256(macFP ‖ tabletFP ‖ macNonce ‖
    /// tabletNonce) as a big-endian integer, mod 1 000 000, zero-padded to 6 digits.
    public static func code(mac: CertificateFingerprint, tablet: CertificateFingerprint, macNonce: Data, tabletNonce: Data) -> String {
        let digest = Data(SHA256.hash(data: mac.bytes + tablet.bytes + macNonce + tabletNonce))
        let value = digest.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return String(format: "%06u", value % 1_000_000)
    }
}

/// Lowercase hex, as fingerprints, commitments and nonces travel in JSON.
public enum Hex {
    public static func encode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Strict: an even number of hex digits and nothing else (no signs, spaces or prefixes).
    public static func decode(_ string: String) -> Data? {
        let digits = Array(string.utf8)
        guard digits.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: digits.count / 2)
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let high = value(of: digits[index]), let low = value(of: digits[index + 1]) else { return nil }
            data.append(high << 4 | low)
        }
        return data
    }

    private static func value(of digit: UInt8) -> UInt8? {
        switch digit {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): digit - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}

/// Authenticates the tablet's `adb reverse` connection. It arrives as a loopback connection,
/// which any process on the Mac (or, through the reverse forward, any app on the tablet) could
/// open too; the Tab2Mac app proves itself with a token the Mac hands it over adb.
public enum LoopbackToken {
    /// A fresh token: 32 random bytes as 64 lowercase hex digits.
    public static func generate() -> String {
        Hex.encode(PairingCode.makeNonce())
    }

    /// Constant-time comparison: how much of a guess matched must not show in the timing.
    public static func matches(_ presented: String?, expected: String) -> Bool {
        guard let presented else { return false }
        let a = Array(presented.utf8), b = Array(expected.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
