package dev.tab2mac.protocol

/**
 * Recycles large byte arrays so that receiving video doesn't create a frame-sized garbage array
 * per frame (power: less GC work on the tablet).
 *
 * Arrays come in power-of-two sizes of at least [minArraySize]; [acquire] returns an array at
 * least as large as requested, so callers track the used length themselves. At most
 * [maxPerSize] arrays of each size are kept; anything beyond that is left to the GC. Releasing
 * an array that didn't come from a pool, or releasing one twice, is harmless. Thread-safe, and
 * allocation-free once warm (fixed slots per size class: no boxing, no iterators).
 */
class ByteArrayPool(
    private val minArraySize: Int = 16 * 1024,
    private val maxPerSize: Int = 4,
) {
    init {
        require(minArraySize > 0 && minArraySize and (minArraySize - 1) == 0) { "minArraySize must be a power of two" }
        require(maxPerSize >= 0) { "maxPerSize must not be negative" }
    }

    private val minShift = Integer.numberOfTrailingZeros(minArraySize)

    /** `slots[sizeClass][i]`: free arrays of `minArraySize shl sizeClass` bytes. */
    private val slots = Array(31 - minShift) { arrayOfNulls<ByteArray>(maxPerSize) }
    private val counts = IntArray(slots.size)
    private var hits = 0L
    private var misses = 0L

    /** An array of at least [minimumSize] bytes, recycled when possible. Contents are undefined. */
    fun acquire(minimumSize: Int): ByteArray {
        require(minimumSize >= 0) { "negative size" }
        val sizeClass = sizeClassOf(minimumSize)
        synchronized(this) {
            val count = counts[sizeClass]
            if (count > 0) {
                val bucket = slots[sizeClass]
                val recycled = bucket[count - 1]!!
                bucket[count - 1] = null
                counts[sizeClass] = count - 1
                hits++
                return recycled
            }
            misses++
        }
        return ByteArray(minArraySize shl sizeClass)
    }

    /** Hands [array] back for reuse. The caller must not touch it afterwards. */
    fun release(array: ByteArray) {
        val size = array.size
        if (size < minArraySize || size and (size - 1) != 0) return
        val sizeClass = Integer.numberOfTrailingZeros(size) - minShift
        if (sizeClass >= slots.size) return
        synchronized(this) {
            val bucket = slots[sizeClass]
            val count = counts[sizeClass]
            if (count >= maxPerSize) return
            // A double release would hand the same array to two owners; ignore it.
            for (i in 0 until count) if (bucket[i] === array) return
            bucket[count] = array
            counts[sizeClass] = count + 1
        }
    }

    /** (recycled, newly allocated) acquisitions so far. */
    val stats: Pair<Long, Long> get() = synchronized(this) { hits to misses }

    private fun sizeClassOf(minimumSize: Int): Int {
        if (minimumSize <= minArraySize) return 0
        val highest = Integer.highestOneBit(minimumSize)
        val size = if (highest == minimumSize) minimumSize else highest shl 1
        return Integer.numberOfTrailingZeros(size) - minShift
    }
}

/** Where [FrameDecoder] gets payload arrays from. The array may be longer than [length]. */
fun interface PayloadAllocator {
    fun allocate(type: MessageType, length: Int): ByteArray

    companion object {
        /** A new exact-size array per frame. */
        val EXACT = PayloadAllocator { _, length -> ByteArray(length) }

        /** VIDEO_FRAME payloads from [pool]; everything else exact-size. */
        fun pooledVideo(pool: ByteArrayPool) = PayloadAllocator { type, length ->
            if (type == MessageType.VIDEO_FRAME) pool.acquire(length) else ByteArray(length)
        }
    }
}
