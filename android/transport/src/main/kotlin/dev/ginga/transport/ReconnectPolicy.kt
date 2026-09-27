package dev.ginga.transport

/**
 * Exponential reconnection backoff (architecture §2.4): 0.25 s, 0.5 s, 1 s, 2 s, 4 s, then 5 s.
 * Pure and deterministic; there is a single client per Mac, so no jitter is needed.
 */
data class ReconnectPolicy(
    val initialDelayMs: Long = 250,
    val maxDelayMs: Long = 5_000,
    val multiplier: Double = 2.0,
) {
    init {
        require(initialDelayMs > 0) { "initialDelayMs must be positive" }
        require(maxDelayMs >= initialDelayMs) { "maxDelayMs must be >= initialDelayMs" }
        require(multiplier >= 1.0) { "multiplier must be >= 1" }
    }

    /** Delay before the next attempt after [consecutiveFailures] (>= 1) failures in a row. */
    fun delayMs(consecutiveFailures: Int): Long {
        require(consecutiveFailures >= 1) { "consecutiveFailures must be >= 1" }
        var delay = initialDelayMs.toDouble()
        repeat(consecutiveFailures - 1) {
            delay *= multiplier
            if (delay >= maxDelayMs) return maxDelayMs
        }
        return minOf(delay.toLong(), maxDelayMs)
    }
}

/**
 * The stateful side of [ReconnectPolicy]: counts consecutive failures. A connection whose
 * handshake completed ([Transport.markHealthy]) resets the count, so the first retry after a
 * working session is quick.
 */
class Backoff(private val policy: ReconnectPolicy = ReconnectPolicy()) {
    /** Failures since the last healthy connection. */
    var consecutiveFailures: Int = 0
        private set

    /** Records a failed or dropped connection and returns how long to wait before retrying. */
    fun nextDelayMs(): Long {
        consecutiveFailures++
        return policy.delayMs(consecutiveFailures)
    }

    /** Records a healthy connection. */
    fun reset() {
        consecutiveFailures = 0
    }
}
