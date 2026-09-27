import Foundation
import Testing
@testable import GingaProtocol

/// The committed vectors in protocol/test-vectors are the cross-language contract (§9).
/// The Kotlin suite runs the same checks against the same files.
@Suite("GoldenVectors")
struct GoldenVectorTests {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // GingaProtocolTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // mac
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("protocol/test-vectors")

    private func committedVectors() throws -> [(name: String, json: JSONValue)] {
        let files = try FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { ($0.deletingPathExtension().lastPathComponent, try JSONValue.parse(Data(contentsOf: $0))) }
    }

    @Test func committedVectorsMatchTheGenerator() throws {
        for vector in try ProtocolTestVectors.all() {
            let file = Self.directory.appendingPathComponent("\(vector.name).json")
            let committed = try Data(contentsOf: file)
            #expect(committed == (try vector.fileData()),
                    "\(vector.name) differs from the generator — vectors are append-only; regenerate only for a new protocol version (ginga protocol-vectors)")
        }
    }

    @Test func everyCommittedVectorDecodesAndReencodes() throws {
        let vectors = try committedVectors()
        #expect(vectors.count >= 19)
        for (name, json) in vectors {
            guard case .string(let hex)? = json["hex"], let bytes = Data(hexString: hex), let expected = json["decoded"] else {
                Issue.record("\(name): malformed vector file")
                continue
            }
            var parser = FrameParser()
            parser.append(bytes)
            let raw = try #require(try parser.next(), "\(name): no complete frame")
            #expect(parser.bufferedByteCount == 0, "\(name): trailing bytes")
            #expect(try ProtocolTestVectors.describe(raw) == expected, "\(name): decoded fields differ")

            guard json["decodeOnly"] != .bool(true) else { continue }
            let reencoded = MessageCodec.encode(try MessageCodec.decode(raw))
            if let type = MessageType(rawValue: raw.type), type.isJSON {
                #expect(reencoded.type == raw.type && reencoded.flags == raw.flags && reencoded.stream == raw.stream, "\(name): header differs")
                #expect(try JSONValue.parse(reencoded.payload) == (try JSONValue.parse(raw.payload)), "\(name): payload differs")
            } else {
                #expect(FrameCodec.encode(reencoded) == bytes, "\(name): re-encoding is not byte-exact")
            }
        }
    }
}
