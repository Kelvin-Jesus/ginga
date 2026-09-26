/// NTP-style clock offset estimation from PING/PONG exchanges (§3.4).
///
/// θ is the responder's clock minus the initiator's clock: a responder timestamp `T`
/// corresponds to initiator time `T − θ`. The estimate uses the sample with the smallest
/// round trip in a sliding window, because queueing delay only ever makes samples worse.
public struct ClockSyncEstimator: Sendable {
    public struct Sample: Hashable, Sendable {
        /// θ in µs.
        public var offset: Int64
        /// Round trip minus responder processing time, µs.
        public var roundTrip: Int64
    }

    public let windowSize: Int
    private var samples: [Sample] = []

    public init(windowSize: Int = 16) {
        precondition(windowSize > 0)
        self.windowSize = windowSize
    }

    /// θ and δ for one exchange: t1 initiator send, t2 responder receive, t3 responder send, t4 initiator receive.
    public static func sample(t1: UInt64, t2: UInt64, t3: UInt64, t4: UInt64) -> Sample {
        let t1 = Int64(bitPattern: t1), t2 = Int64(bitPattern: t2), t3 = Int64(bitPattern: t3), t4 = Int64(bitPattern: t4)
        return Sample(offset: ((t2 - t1) + (t3 - t4)) / 2, roundTrip: (t4 - t1) - (t3 - t2))
    }

    @discardableResult
    public mutating func add(t1: UInt64, t2: UInt64, t3: UInt64, t4: UInt64) -> Sample {
        let sample = Self.sample(t1: t1, t2: t2, t3: t3, t4: t4)
        guard sample.roundTrip >= 0 else { return sample }  // clock went backwards or bogus reply
        samples.append(sample)
        if samples.count > windowSize { samples.removeFirst(samples.count - windowSize) }
        return sample
    }

    /// The best current estimate (minimum round trip in the window).
    public var best: Sample? {
        samples.min { $0.roundTrip < $1.roundTrip }
    }

    public var sampleCount: Int { samples.count }
}
