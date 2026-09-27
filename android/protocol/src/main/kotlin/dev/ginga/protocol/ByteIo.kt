package dev.ginga.protocol

/** Big-endian writer for the binary parts of the protocol (§1: all integers are big-endian). */
class ByteWriter(initialCapacity: Int = 64) {
    private var buffer = ByteArray(initialCapacity.coerceAtLeast(0))

    /** Bytes written so far. */
    var size: Int = 0
        private set

    fun u8(value: Int): ByteWriter = apply {
        ensure(1)
        buffer[size++] = value.toByte()
    }

    fun u16(value: Int): ByteWriter = apply {
        ensure(2)
        buffer[size++] = (value ushr 8).toByte()
        buffer[size++] = value.toByte()
    }

    /** Two's complement 16-bit value. */
    fun i16(value: Int): ByteWriter = u16(value and 0xFFFF)

    fun u32(value: Long): ByteWriter = apply {
        ensure(4)
        for (shift in 24 downTo 0 step 8) buffer[size++] = (value ushr shift).toByte()
    }

    /** Unsigned 64-bit value carried in a Long's bit pattern. */
    fun u64(value: Long): ByteWriter = apply {
        ensure(8)
        for (shift in 56 downTo 0 step 8) buffer[size++] = (value ushr shift).toByte()
    }

    fun bytes(value: ByteArray, offset: Int = 0, length: Int = value.size - offset): ByteWriter = apply {
        ensure(length)
        value.copyInto(buffer, size, offset, offset + length)
        size += length
    }

    /** The bytes written; no copy when the writer was sized exactly (the writer must not be reused). */
    fun toByteArray(): ByteArray = if (size == buffer.size) buffer else buffer.copyOf(size)

    private fun ensure(extra: Int) {
        if (size + extra > buffer.size) buffer = buffer.copyOf(maxOf(buffer.size * 2, size + extra, 16))
    }
}

/**
 * Bounds-checked big-endian reader over `bytes[start until end]`. Every read throws
 * [ProtocolException.Truncated] instead of an index exception.
 */
class ByteReader(
    private val bytes: ByteArray,
    private val start: Int = 0,
    private val end: Int = bytes.size,
    private val context: String,
) {
    private var cursor = start

    /** Position relative to `start`. */
    val position: Int get() = cursor - start

    /** Bytes not read yet. */
    val remaining: Int get() = end - cursor

    fun u8(): Int {
        need(1)
        return bytes[cursor++].toInt() and 0xFF
    }

    fun u16(): Int {
        need(2)
        val value = ((bytes[cursor].toInt() and 0xFF) shl 8) or (bytes[cursor + 1].toInt() and 0xFF)
        cursor += 2
        return value
    }

    /** Two's complement 16-bit value. */
    fun i16(): Int = u16().toShort().toInt()

    fun u32(): Long {
        need(4)
        var value = 0L
        repeat(4) { value = (value shl 8) or (bytes[cursor++].toLong() and 0xFF) }
        return value
    }

    /** Unsigned 64-bit value returned as a Long bit pattern. */
    fun u64(): Long {
        need(8)
        var value = 0L
        repeat(8) { value = (value shl 8) or (bytes[cursor++].toLong() and 0xFF) }
        return value
    }

    /** Everything not read yet. */
    fun rest(): ByteArray {
        val result = bytes.copyOfRange(cursor, end)
        cursor = end
        return result
    }

    /** Moves forward to [target] (relative to `start`), skipping fields appended by newer peers. */
    fun skipTo(target: Int) {
        if (target < position) {
            throw ProtocolException.Malformed("$context: cannot skip backwards to $target from $position")
        }
        need(target - position)
        cursor = start + target
    }

    private fun need(count: Int) {
        if (count < 0 || remaining < count) {
            throw ProtocolException.Truncated("$context: need $count byte(s) at offset $position, have $remaining")
        }
    }
}

/** Lowercase hexadecimal, as used by the golden test vectors and logs. */
fun ByteArray.toHex(): String {
    val digits = "0123456789abcdef"
    val out = CharArray(size * 2)
    for (i in indices) {
        val v = this[i].toInt() and 0xFF
        out[2 * i] = digits[v ushr 4]
        out[2 * i + 1] = digits[v and 0x0F]
    }
    return String(out)
}

/** Parses [toHex] output (either case). */
fun String.hexToBytes(): ByteArray {
    require(length % 2 == 0) { "hex string has odd length $length" }
    return ByteArray(length / 2) { i ->
        val high = Character.digit(this[2 * i], 16)
        val low = Character.digit(this[2 * i + 1], 16)
        require(high >= 0 && low >= 0) { "invalid hex at ${2 * i}" }
        ((high shl 4) or low).toByte()
    }
}
