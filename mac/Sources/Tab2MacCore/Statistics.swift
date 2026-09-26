/// A fixed-capacity window over the most recent samples (e.g. per-frame latencies in ms).
public struct SampleWindow: Sendable {
    public let capacity: Int
    private var storage: [Double] = []
    private var nextIndex = 0

    public init(capacity: Int) {
        precondition(capacity > 0, "SampleWindow capacity must be positive")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public mutating func add(_ value: Double) {
        if storage.count < capacity {
            storage.append(value)
        } else {
            storage[nextIndex] = value
        }
        nextIndex = (nextIndex + 1) % capacity
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        nextIndex = 0
    }

    public var count: Int { storage.count }

    /// The retained samples, in no particular order.
    public var values: [Double] { storage }

    public var mean: Double? {
        storage.isEmpty ? nil : storage.reduce(0, +) / Double(storage.count)
    }

    public var min: Double? { storage.min() }
    public var max: Double? { storage.max() }

    /// Population standard deviation.
    public var standardDeviation: Double? {
        guard let mean else { return nil }
        let variance = storage.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(storage.count)
        return variance.squareRoot()
    }

    /// Nearest-rank percentile; `p` in 0...1.
    public func percentile(_ p: Double) -> Double? {
        guard !storage.isEmpty else { return nil }
        return Self.percentile(p, ofSorted: storage.sorted())
    }

    public var summary: StatisticSummary? {
        guard let mean, let standardDeviation else { return nil }
        let sorted = storage.sorted()
        return StatisticSummary(
            count: sorted.count,
            mean: mean,
            min: sorted[0],
            max: sorted[sorted.count - 1],
            p50: Self.percentile(0.50, ofSorted: sorted),
            p95: Self.percentile(0.95, ofSorted: sorted),
            p99: Self.percentile(0.99, ofSorted: sorted),
            standardDeviation: standardDeviation
        )
    }

    private static func percentile(_ p: Double, ofSorted sorted: [Double]) -> Double {
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[Swift.min(Swift.max(rank, 1), sorted.count) - 1]
    }
}

/// Summary statistics of a sample window, suitable for diagnostics and JSON reports.
public struct StatisticSummary: Hashable, Sendable, Codable {
    public var count: Int
    public var mean: Double
    public var min: Double
    public var max: Double
    public var p50: Double
    public var p95: Double
    public var p99: Double
    public var standardDeviation: Double
}

/// Events (or amounts, e.g. bytes) per second over a sliding time window. Times passed in must
/// be non-decreasing. Pruning is amortized O(1): old entries are skipped, then compacted.
public struct RateMeter: Sendable {
    public let window: Duration
    private var entries: [(time: MediaTime, amount: Double)] = []
    private var head = 0
    private var total = 0.0

    public init(window: Duration) {
        precondition(window > .zero, "RateMeter window must be positive")
        self.window = window
    }

    public mutating func record(at time: MediaTime, amount: Double = 1) {
        entries.append((time, amount))
        total += amount
        prune(before: time)
    }

    /// Events (or the recorded amount) per second in the window `(time - window, time]`.
    public mutating func rate(at time: MediaTime) -> Double {
        prune(before: time)
        return (head == entries.count ? 0 : total) / window.inSeconds
    }

    private mutating func prune(before time: MediaTime) {
        while head < entries.count, time - entries[head].time >= window {
            total -= entries[head].amount
            head += 1
        }
        if head > 1024, head * 2 > entries.count {
            entries.removeFirst(head)
            head = 0
        }
    }
}
