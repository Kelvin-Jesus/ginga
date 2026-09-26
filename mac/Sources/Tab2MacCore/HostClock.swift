import Darwin

/// The ratio that converts `mach_absolute_time()` ticks into nanoseconds.
///
/// On Apple Silicon this is 125/3 (ticks run at 24 MHz), so ticks must never be treated as nanoseconds.
public struct HostTimebase: Hashable, Sendable {
    public let numer: UInt32
    public let denom: UInt32

    public init(numer: UInt32, denom: UInt32) {
        precondition(numer > 0 && denom > 0, "invalid mach timebase \(numer)/\(denom)")
        self.numer = numer
        self.denom = denom
    }

    /// The timebase of the running host.
    public static let current: HostTimebase = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return HostTimebase(numer: info.numer, denom: info.denom)
    }()

    public func nanoseconds(fromTicks ticks: UInt64) -> UInt64 {
        Self.scale(ticks, by: UInt64(numer), dividedBy: UInt64(denom))
    }

    public func ticks(fromNanoseconds nanoseconds: UInt64) -> UInt64 {
        Self.scale(nanoseconds, by: UInt64(denom), dividedBy: UInt64(numer))
    }

    /// `floor(value * multiplier / divisor)` without intermediate overflow; saturates at `UInt64.max`.
    private static func scale(_ value: UInt64, by multiplier: UInt64, dividedBy divisor: UInt64) -> UInt64 {
        let product = value.multipliedFullWidth(by: multiplier)
        guard product.high < divisor else { return .max }
        return divisor.dividingFullWidth(product).quotient
    }
}

/// A point on the host's monotonic clock (`mach_absolute_time`), in nanoseconds.
///
/// ScreenCaptureKit display times and the CoreMedia host-time clock are based on the same clock,
/// so capture timestamps and locally measured times can be compared directly.
public struct MediaTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let nanoseconds: UInt64

    public init(nanoseconds: UInt64) {
        self.nanoseconds = nanoseconds
    }

    public init(hostTicks: UInt64, timebase: HostTimebase = .current) {
        self.nanoseconds = timebase.nanoseconds(fromTicks: hostTicks)
    }

    public static func now() -> MediaTime {
        MediaTime(hostTicks: mach_absolute_time())
    }

    public func hostTicks(timebase: HostTimebase = .current) -> UInt64 {
        timebase.ticks(fromNanoseconds: nanoseconds)
    }

    public func advanced(by duration: Duration) -> MediaTime {
        let delta = duration.totalNanoseconds
        if delta >= 0 {
            return MediaTime(nanoseconds: nanoseconds &+ UInt64(delta))
        }
        let magnitude = delta.magnitude
        return MediaTime(nanoseconds: magnitude > nanoseconds ? 0 : nanoseconds - magnitude)
    }

    public static func < (lhs: MediaTime, rhs: MediaTime) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }

    /// Signed distance between two times (valid while both are within ~292 years of boot).
    public static func - (lhs: MediaTime, rhs: MediaTime) -> Duration {
        .nanoseconds(Int64(bitPattern: lhs.nanoseconds &- rhs.nanoseconds))
    }

    public var description: String {
        "\(Double(nanoseconds) / 1e9)s"
    }
}

extension Duration {
    /// The duration as fractional milliseconds (for display and statistics).
    public var inMilliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }

    /// The duration as fractional seconds.
    public var inSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    /// The duration truncated to whole nanoseconds.
    public var totalNanoseconds: Int64 {
        components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
    }
}
