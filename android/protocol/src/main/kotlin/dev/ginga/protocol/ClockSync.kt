package dev.ginga.protocol

/**
 * One PING/PONG exchange (§3.4).
 *
 * @property offsetUs θ = responder clock − initiator clock. When Android pings, θ = Mac − Android,
 *   so a Mac timestamp `T` corresponds to Android time `T − θ`.
 * @property roundTripUs δ = round trip minus the responder's processing time.
 */
data class ClockSample(val offsetUs: Long, val roundTripUs: Long)

/**
 * NTP-style clock offset estimation (§3.4): keeps the θ of the minimum-δ sample over a sliding
 * window, because queueing delay only ever makes samples worse.
 *
 * Not thread-safe.
 */
class ClockSyncEstimator(val windowSize: Int = DEFAULT_WINDOW) {
    init {
        require(windowSize > 0) { "windowSize must be positive" }
    }

    private val samples = ArrayDeque<ClockSample>(windowSize)

    /** The most recent valid sample. */
    var latest: ClockSample? = null
        private set

    /** Valid samples in the window. */
    val sampleCount: Int get() = samples.size

    /** The best current estimate: the minimum-δ sample in the window. */
    val best: ClockSample? get() = samples.minByOrNull { it.roundTripUs }

    /**
     * Adds the exchange `t1` initiator send, `t2` responder receive, `t3` responder send, `t4`
     * initiator receive (all µs, each on its own clock). Samples with a negative δ (a clock went
     * backwards, or a bogus reply) are returned but not kept.
     */
    fun add(t1: Long, t2: Long, t3: Long, t4: Long): ClockSample {
        val sample = sample(t1, t2, t3, t4)
        if (sample.roundTripUs < 0) return sample
        samples.addLast(sample)
        while (samples.size > windowSize) samples.removeFirst()
        latest = sample
        return sample
    }

    /** Forgets every sample, e.g. when a connection to a possibly different Mac starts. */
    fun reset() {
        samples.clear()
        latest = null
    }

    companion object {
        /** "About 16 samples" (§3.4). */
        const val DEFAULT_WINDOW: Int = 16

        /** θ and δ of one exchange; see [ClockSample]. */
        fun sample(t1: Long, t2: Long, t3: Long, t4: Long): ClockSample =
            ClockSample(offsetUs = ((t2 - t1) + (t3 - t4)) / 2, roundTripUs = (t4 - t1) - (t3 - t2))
    }
}
