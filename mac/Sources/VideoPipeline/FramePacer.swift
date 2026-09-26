import Foundation
import os

/// "Latest frame wins" in front of a stage (encoder, transport).
///
/// At most `maxInFlight` items are being processed; while the stage is busy, a newer item
/// replaces the waiting one (counted as dropped). Latency therefore never accumulates in a queue.
/// Thread-safe: `offer` and `completed` may be called from any thread.
public final class FramePacer<Item: Sendable>: Sendable {
    private struct State {
        var inFlight = 0
        var pending: Item?
        var dropped = 0
    }

    public let maxInFlight: Int
    private let state: OSAllocatedUnfairLock<State>
    private let process: @Sendable (Item) -> Void

    public init(maxInFlight: Int = 1, process: @escaping @Sendable (Item) -> Void) {
        precondition(maxInFlight > 0)
        self.maxInFlight = maxInFlight
        self.state = OSAllocatedUnfairLock(uncheckedState: State())
        self.process = process
    }

    public var droppedCount: Int { state.withLockUnchecked { $0.dropped } }
    public var inFlightCount: Int { state.withLockUnchecked { $0.inFlight } }

    /// Offers a new item; processes it now or keeps it as the one waiting item.
    public func offer(_ item: Item) {
        let runNow: Bool = state.withLockUnchecked { state in
            if state.inFlight < maxInFlight {
                state.inFlight += 1
                return true
            }
            if state.pending != nil { state.dropped += 1 }
            state.pending = item
            return false
        }
        if runNow { process(item) }
    }

    /// The stage finished one item; starts the waiting one, if any.
    public func completed() {
        let next: Item? = state.withLockUnchecked { state in
            if let pending = state.pending {
                state.pending = nil
                return pending
            }
            state.inFlight = max(0, state.inFlight - 1)
            return nil
        }
        if let next { process(next) }
    }

    /// Forgets the waiting item and in-flight accounting (after a stage restart).
    public func reset() {
        state.withLockUnchecked { state in
            state.pending = nil
            state.inFlight = 0
        }
    }
}
