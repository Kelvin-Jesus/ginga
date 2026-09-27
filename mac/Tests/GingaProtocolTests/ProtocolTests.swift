import Foundation
import Testing
@testable import GingaProtocol

private let sampleMessages: [Message] = [
    .hello(Hello(
        versions: .init(min: 1, max: 1), app: .init(name: "Test", version: "1"),
        device: .init(manufacturer: "samsung", model: "SM-X730", android: "16", id: "abc"),
        display: .init(widthPx: 2560, heightPx: 1600, densityDpi: 274, refreshRates: [60, 120], rotation: 0),
        decoders: [.init(mime: "video/hevc", profiles: ["main"], maxWidth: 4096, maxHeight: 2176, maxFps: 120, lowLatency: true)],
        input: nil, transport: "adb-tcp", features: nil
    )),
    .keyframeRequest(KeyframeRequest(reason: "startup")),
    .receiverReport(ReceiverReport(framesReceived: 3)),
    .streamFormat(StreamFormat(codec: "hevc", width: 2560, height: 1600, parameterSets: [Data([1, 2, 3]), Data([4])])),
    .videoFrame(VideoFrame(frameId: .max, captureTimeUs: .max, encodeDurationUs: 1, isKeyframe: true, data: Data(repeating: 7, count: 70_000))),
    .input(InputMessage(sequence: 3, eventTimeUs: 99, kind: .stylus, action: .hoverExit,
                        pointers: [PointerRecord(pointerId: 9, toolType: .eraser, buttons: [.stylusPrimary, .secondary], x: 65535, y: 0, pressure: 1, tiltX: -32767, tiltY: 32767, distance: 5)])),
    .input(InputMessage(sequence: 4, eventTimeUs: 100, kind: .touch, action: .cancel, pointers: [])),
    .ping(Ping(id: 1, t1: 2)),
    .pong(Pong(id: 1, t1: 2, t2: 3, t3: 4)),
    .goodbye(Goodbye(reason: "shutdown")),
]

@Suite("Framing")
struct FramingTests {
    @Test func headerLayoutMatchesTheSpecification() {
        let data = FrameCodec.encode(RawMessage(type: 0x20, flags: [.ignorable, .keyframe], stream: .telemetry, payload: Data([1, 2, 3])))
        #expect(Array(data) == [0x47, 0x4E, 0x01, 0x20, 0x00, 0x03, 0x00, 0x04, 0x00, 0x00, 0x00, 0x03, 1, 2, 3])
    }

    @Test func parserReassemblesByteByByteDelivery() throws {
        let bytes = sampleMessages.map(MessageCodec.frame).reduce(Data(), +)
        var parser = FrameParser()
        var decoded: [Message] = []
        for byte in bytes {
            parser.append(Data([byte]))
            while let raw = try parser.next() { decoded.append(try MessageCodec.decode(raw)) }
        }
        #expect(decoded == sampleMessages)
        #expect(parser.bufferedByteCount == 0)
    }

    @Test func parserSplitsCoalescedMessages() throws {
        var parser = FrameParser()
        parser.append(sampleMessages.map(MessageCodec.frame).reduce(Data(), +))
        var count = 0
        while try parser.next() != nil { count += 1 }
        #expect(count == sampleMessages.count)
    }

    @Test func incompleteInputYieldsNothingYet() throws {
        var parser = FrameParser()
        let frame = MessageCodec.frame(.ping(Ping(id: 1, t1: 1)))
        parser.append(frame.prefix(11))
        #expect(try parser.next() == nil)
        parser.append(frame.dropFirst(11).prefix(3))
        #expect(try parser.next() == nil)
        parser.append(frame.dropFirst(14))
        #expect(try parser.next() != nil)
    }

    @Test func rejectsBadMagicVersionAndOversizedPayloads() {
        var parser = FrameParser()
        parser.append(Data([0x00, 0x00, 1, 0x20, 0, 0, 0, 0, 0, 0, 0, 0]))
        #expect(throws: ProtocolError.badMagic(0)) { try parser.next() }

        parser = FrameParser()
        parser.append(Data([0x47, 0x4E, 2, 0x20, 0, 0, 0, 0, 0, 0, 0, 0]))
        #expect(throws: ProtocolError.unsupportedFramingVersion(2)) { try parser.next() }

        parser = FrameParser()
        parser.append(Data([0x47, 0x4E, 1, 0x10, 0, 0, 0, 1, 0x01, 0x00, 0x00, 0x01]))
        #expect(throws: ProtocolError.payloadTooLarge(16_777_217)) { try parser.next() }
    }
}

@Suite("MessageCodec")
struct MessageCodecTests {
    /// The single-copy VIDEO_FRAME path must produce exactly the generic framing.
    @Test func videoFramesFrameIdenticallyOnTheFastPath() {
        for keyframe in [true, false] {
            let frame = VideoFrame(frameId: 7, captureTimeUs: 123_456_789, encodeDurationUs: 5_900, isKeyframe: keyframe, data: Data((0..<1000).map { UInt8($0 % 251) }))
            #expect(MessageCodec.frame(.videoFrame(frame)) == FrameCodec.encode(MessageCodec.encode(.videoFrame(frame))))
        }
    }

    @Test func everyMessageRoundTrips() throws {
        for message in sampleMessages {
            var parser = FrameParser()
            parser.append(MessageCodec.frame(message))
            let raw = try #require(try parser.next())
            #expect(try MessageCodec.decode(raw) == message)
        }
    }

    @Test func messagesTravelOnTheirSpecifiedStreams() {
        #expect(MessageCodec.encode(.ping(Ping(id: 0, t1: 0))).stream == .control)
        #expect(MessageCodec.encode(.keyframeRequest(KeyframeRequest(reason: "loss"))).stream == .video)
        #expect(MessageCodec.encode(.input(InputMessage(sequence: 0, eventTimeUs: 0, kind: .touch, action: .down, pointers: []))).stream == .input)
        #expect(MessageCodec.encode(.receiverReport(ReceiverReport())).stream == .telemetry)
    }

    @Test func keyframeFlagFollowsTheFrame() {
        #expect(MessageCodec.encode(.videoFrame(VideoFrame(frameId: 0, captureTimeUs: 0, encodeDurationUs: 0, isKeyframe: true, data: Data()))).flags == [.keyframe])
        #expect(MessageCodec.encode(.videoFrame(VideoFrame(frameId: 0, captureTimeUs: 0, encodeDurationUs: 0, isKeyframe: false, data: Data()))).flags == [])
    }

    /// Unknown types are handed to the session either way: it skips IGNORABLE ones and answers the
    /// rest with ERROR "unsupported", keeping the connection (§1).
    @Test func unknownTypesReachTheSession() throws {
        let ignorable = RawMessage(type: 0x7F, flags: [.ignorable], stream: .control, payload: Data())
        #expect(try MessageCodec.decode(ignorable) == .unknown(ignorable))
        let required = RawMessage(type: 0x7F, flags: [], stream: .control, payload: Data())
        #expect(try MessageCodec.decode(required) == .unknown(required))
    }

    @Test func pairingIsIgnorableJSONOnTheControlStream() throws {
        let raw = MessageCodec.encode(.pairing(Pairing(state: .required, name: "Mac")))
        #expect(raw.type == 0x07 && raw.flags == [.ignorable] && raw.stream == .control)
        #expect(String(decoding: raw.payload, as: UTF8.self) == #"{"name":"Mac","state":"required"}"#)
        #expect(try MessageCodec.decode(raw) == .pairing(Pairing(state: .required, name: "Mac")))
    }

    @Test func truncatedBinaryPayloadsAreErrorsNotCrashes() {
        for type in [MessageType.videoFrame, .input, .ping, .pong] {
            #expect(throws: ProtocolError.self) {
                try MessageCodec.decode(RawMessage(type: type.rawValue, flags: [], stream: type.stream, payload: Data([0x00, 0x12, 0x01])))
            }
        }
    }

    @Test func headerLengthsBelowVersionOneAreRejected() {
        #expect(throws: ProtocolError.self) {
            try MessageCodec.decode(RawMessage(type: MessageType.videoFrame.rawValue, flags: [], stream: .video, payload: Data([0x00, 0x04, 0, 0])))
        }
    }

    @Test func jsonIgnoresUnknownKeysAndDefaultsMissingOptionals() throws {
        let raw = RawMessage(type: MessageType.receiverReport.rawValue, flags: [], stream: .telemetry, payload: Data(#"{"future":{"x":1},"framesReceived":5}"#.utf8))
        #expect(try MessageCodec.decode(raw) == .receiverReport(ReceiverReport(framesReceived: 5)))
    }

    @Test func invalidJSONIsReportedWithTheMessageName() {
        #expect {
            try MessageCodec.decode(RawMessage(type: MessageType.hello.rawValue, flags: [], stream: .control, payload: Data("{".utf8)))
        } throws: { error in
            if case .invalidJSON(let message, _) = error as? ProtocolError { return message == "HELLO" }
            return false
        }
    }

    @Test func versionNegotiationPicksTheHighestCommonVersion() {
        #expect(VersionNegotiation.negotiate(local: .init(min: 1, max: 3), remote: .init(min: 2, max: 5)) == 3)
        #expect(VersionNegotiation.negotiate(local: .init(min: 1, max: 1), remote: .init(min: 1, max: 2)) == 1)
        #expect(VersionNegotiation.negotiate(local: .init(min: 1, max: 1), remote: .init(min: 2, max: 2)) == nil)
    }
}

@Suite("ClockSync")
struct ClockSyncTests {
    @Test func computesOffsetAndRoundTrip() {
        // Responder clock is ~5 s ahead; 300 µs on the wire, 100 µs processing.
        let sample = ClockSyncEstimator.sample(t1: 1_000, t2: 5_000_100, t3: 5_000_200, t4: 1_400)
        #expect(sample.offset == 4_998_950)
        #expect(sample.roundTrip == 300)
    }

    @Test func usesTheLowestRoundTripSample() {
        var estimator = ClockSyncEstimator()
        estimator.add(t1: 0, t2: 1_000_500, t3: 1_000_500, t4: 2_000)  // slow, skewed
        estimator.add(t1: 10_000, t2: 1_010_100, t3: 1_010_100, t4: 10_200)  // fast
        #expect(estimator.best?.roundTrip == 200)
        #expect(estimator.best?.offset == 1_000_000)
    }

    @Test func slidingWindowForgetsOldSamples() {
        var estimator = ClockSyncEstimator(windowSize: 2)
        estimator.add(t1: 0, t2: 50, t3: 50, t4: 100)
        estimator.add(t1: 1_000, t2: 1_200, t3: 1_200, t4: 1_400)
        estimator.add(t1: 2_000, t2: 2_300, t3: 2_300, t4: 2_600)
        #expect(estimator.sampleCount == 2)
        #expect(estimator.best?.roundTrip == 400)
    }

    @Test func ignoresImpossibleSamples() {
        var estimator = ClockSyncEstimator()
        estimator.add(t1: 100, t2: 0, t3: 1_000, t4: 150)  // responder took longer than the round trip
        #expect(estimator.best == nil)
    }
}
