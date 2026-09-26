import Tab2MacCore

/// Adaptive bitrate for lossy links (Wi‑Fi, M7): additive increase, multiplicative decrease,
/// driven by the receiver's reports (every 250 ms on Wi‑Fi) and the Mac's own backpressure.
///
/// Congestion shows up first as queueing delay, well before loss: end-to-end latency rises above
/// its recent floor. The controller backs off on that, on frames the Mac had to skip because the
/// link was full, and on frames the tablet dropped. Otherwise it probes upward slowly. USB links
/// don't use it: their bitrate stays fixed.
public struct BitrateController: Sendable {
    public struct Limits: Sendable, Equatable {
        public var minimumKbps: Int
        public var startKbps: Int
        public var maximumKbps: Int

        public init(minimumKbps: Int = 2_000, startKbps: Int = 12_000, maximumKbps: Int = 30_000) {
            self.minimumKbps = minimumKbps
            self.startKbps = startKbps
            self.maximumKbps = maximumKbps
        }
    }

    /// One report interval, as the controller sees it.
    public struct Sample: Sendable, Equatable {
        public var time: MediaTime
        /// End-to-end p50 over the interval (ms), from the receiver.
        public var endToEndP50Milliseconds: Double?
        public var framesDropped: Int
        /// Frames the Mac skipped before encoding because the link was still busy.
        public var framesSkippedForBackpressure: Int

        public init(time: MediaTime, endToEndP50Milliseconds: Double?, framesDropped: Int, framesSkippedForBackpressure: Int) {
            self.time = time
            self.endToEndP50Milliseconds = endToEndP50Milliseconds
            self.framesDropped = framesDropped
            self.framesSkippedForBackpressure = framesSkippedForBackpressure
        }
    }

    public let limits: Limits
    public private(set) var targetKbps: Int
    /// Queueing delay (ms above the latency floor) that counts as congestion.
    public var delayThresholdMilliseconds = 25.0
    public var decreaseFactor = 0.7
    /// Additive step per stable interval, as a fraction of the maximum.
    public var increaseStep = 0.04
    /// No increase this soon after a decrease: let the queue drain first.
    public var holdAfterDecrease: Duration = .seconds(2)

    private var floorWindow: [(time: MediaTime, latency: Double)] = []
    private var lastDecrease: MediaTime?

    public init(limits: Limits = Limits()) {
        self.limits = limits
        self.targetKbps = limits.startKbps
    }

    /// The lowest recent end-to-end latency: the link's delay without queueing.
    public var latencyFloorMilliseconds: Double? { floorWindow.map(\.latency).min() }

    /// Feeds one report interval; returns the new target when it changed.
    public mutating func update(_ sample: Sample) -> Int? {
        if let latency = sample.endToEndP50Milliseconds {
            floorWindow.append((sample.time, latency))
            floorWindow.removeAll { sample.time - $0.time > .seconds(10) }
        }
        let queueing = both(sample.endToEndP50Milliseconds, latencyFloorMilliseconds).map { $0.0 - $0.1 } ?? 0
        let congested = sample.framesSkippedForBackpressure > 0 || sample.framesDropped > 0 || queueing > delayThresholdMilliseconds

        let previous = targetKbps
        if congested {
            // One decrease per hold period: several reports describe the same queue.
            if lastDecrease.map({ sample.time - $0 >= holdAfterDecrease / 2 }) ?? true {
                targetKbps = max(limits.minimumKbps, Int(Double(targetKbps) * decreaseFactor))
                lastDecrease = sample.time
            }
        } else if lastDecrease.map({ sample.time - $0 >= holdAfterDecrease }) ?? true {
            targetKbps = min(limits.maximumKbps, targetKbps + Int(Double(limits.maximumKbps) * increaseStep))
        }
        return targetKbps == previous ? nil : targetKbps
    }
}

private func both<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
