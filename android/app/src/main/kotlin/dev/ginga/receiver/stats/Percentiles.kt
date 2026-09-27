package dev.ginga.receiver.stats

import kotlin.math.ceil

/** p50 and p95 of a set of samples. */
data class LatencySummary(val p50: Double, val p95: Double, val count: Int) {
    companion object {
        /** Nearest-rank percentiles; null when [samples] is empty. */
        fun of(samples: DoubleArray, count: Int = samples.size): LatencySummary? {
            if (count <= 0) return null
            val sorted = samples.copyOf(count).also { it.sort() }
            return LatencySummary(percentile(sorted, 50.0), percentile(sorted, 95.0), count)
        }

        /** Nearest-rank percentile of an ascending array. */
        fun percentile(sorted: DoubleArray, p: Double): Double {
            require(sorted.isNotEmpty()) { "no samples" }
            val rank = ceil(p / 100.0 * sorted.size).toInt().coerceIn(1, sorted.size)
            return sorted[rank - 1]
        }
    }
}

/** The most recent [capacity] samples (a ring buffer). Not thread-safe. */
class PercentileWindow(private val capacity: Int) {
    init {
        require(capacity > 0) { "capacity must be positive" }
    }

    private val values = DoubleArray(capacity)
    private var next = 0

    /** Samples held (at most [capacity]). */
    var count: Int = 0
        private set

    fun add(value: Double) {
        values[next] = value
        next = (next + 1) % capacity
        if (count < capacity) count++
    }

    fun clear() {
        next = 0
        count = 0
    }

    /** p50/p95 of the held samples, or null when empty. */
    fun summary(): LatencySummary? = LatencySummary.of(values, count)
}

/** Samples collected since the last [drain] (e.g. one RECEIVER_REPORT interval). Not thread-safe. */
class IntervalSamples(initialCapacity: Int = 64) {
    private var values = DoubleArray(initialCapacity.coerceAtLeast(1))
    private var count = 0

    fun add(value: Double) {
        if (count == values.size) values = values.copyOf(values.size * 2)
        values[count++] = value
    }

    /** p50/p95 of the interval, then starts a new one. */
    fun drain(): LatencySummary? {
        val summary = LatencySummary.of(values, count)
        count = 0
        return summary
    }
}
