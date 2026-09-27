import GingaCore

/// Caps a stream at `frameRate` from capture timestamps, dropping (never delaying) frames.
///
/// Frames fill slots on a fixed schedule: a frame is taken when it reaches the next slot (less a
/// small jitter tolerance). A 120 Hz source streamed at 60 fps therefore sends exactly every
/// second frame, and any faster source averages exactly `frameRate`. A late frame re-anchors the
/// schedule instead of letting the next one catch up, so frames are never sent in bursts.
///
/// When the source is known to be no faster than the rate (`sourceRate`, the display's refresh),
/// every frame passes: there is nothing to cap, and a schedule would only turn timestamp jitter
/// into dropped frames.
public struct FrameCadence: Sendable {
    public var frameRate: Double
    /// How fast frames can arrive (the display's refresh rate), if known.
    public var sourceRate: Double?
    private var nextSlot: MediaTime?

    public init(frameRate: Double, sourceRate: Double? = nil) {
        self.frameRate = frameRate
        self.sourceRate = sourceRate
    }

    /// Whether every frame passes (the source is no faster than the rate, within half a hertz).
    public var isPassthrough: Bool {
        sourceRate.map { $0 <= frameRate + 0.5 } ?? false
    }

    public var interval: Duration {
        .nanoseconds(Int64(1e9 / max(frameRate, 1)))
    }

    /// Timestamp jitter accepted around a slot: a quarter interval, at most 4 ms.
    public var tolerance: Duration {
        min(.milliseconds(4), interval / 4)
    }

    /// Whether a frame captured at `time` is due. Doesn't consume the slot; call `take` once the
    /// frame is actually sent (a frame refused later, e.g. by backpressure, leaves the slot open).
    public func admits(_ time: MediaTime) -> Bool {
        guard !isPassthrough, let nextSlot else { return true }
        return time - nextSlot >= .zero - tolerance
    }

    public mutating func take(_ time: MediaTime) {
        if let slot = nextSlot, abs((time - slot).totalNanoseconds) <= tolerance.totalNanoseconds {
            nextSlot = slot.advanced(by: interval)  // on schedule: keep the phase
        } else {
            nextSlot = time.advanced(by: interval)  // first frame, or late: re-anchor
        }
    }

    public mutating func reset() {
        nextSlot = nil
    }
}
