package dev.ginga.protocol

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotSame
import kotlin.test.assertSame
import kotlin.test.assertTrue

class ByteArrayPoolTest {
    @Test
    fun sizesArePowersOfTwoAtLeastTheMinimum() {
        val pool = ByteArrayPool(minArraySize = 16 * 1024)
        assertEquals(16 * 1024, pool.acquire(10).size)
        assertEquals(16 * 1024, pool.acquire(16 * 1024).size)
        assertEquals(32 * 1024, pool.acquire(16 * 1024 + 1).size)
        assertEquals(1 shl 20, pool.acquire(600_000).size)
    }

    @Test
    fun releasedArraysAreReused() {
        val pool = ByteArrayPool()
        val first = pool.acquire(100_000)
        pool.release(first)
        assertSame(first, pool.acquire(90_000))
        assertNotSame(first, pool.acquire(90_000), "the only pooled array is in use")
        assertEquals(1L to 2L, pool.stats)
    }

    @Test
    fun aDoubleReleaseDoesNotCreateTwoOwners() {
        val pool = ByteArrayPool(minArraySize = 1024)
        val array = pool.acquire(1024)
        pool.release(array)
        pool.release(array)
        assertSame(array, pool.acquire(1024))
        assertNotSame(array, pool.acquire(1024))
    }

    @Test
    fun retentionIsBoundedAndForeignArraysAreIgnored() {
        val pool = ByteArrayPool(minArraySize = 1024, maxPerSize = 2)
        val arrays = List(3) { pool.acquire(1024) }
        arrays.forEach(pool::release)
        pool.release(ByteArray(1500)) // not a pool size
        val again = List(3) { pool.acquire(1024) }
        assertEquals(2, again.count { candidate -> arrays.any { it === candidate } })
    }

    @Test
    fun frameDecoderCanDecodeIntoPooledArrays() {
        val pool = ByteArrayPool(minArraySize = 1024)
        val video = MessageCodec.encode(VideoFrame(1, 2, 3, isKeyframe = true, data = ByteArray(3000) { it.toByte() }))
        val ping = MessageCodec.encode(Ping(1, 2))
        val decoder = FrameDecoder(allocator = PayloadAllocator.pooledVideo(pool))
        val frames = decoder.feed(FrameCodec.encode(video) + FrameCodec.encode(ping))
        assertEquals(listOf(video, ping), frames)
        assertEquals(4096, frames[0].payload.size, "pooled array")
        assertEquals(video.payloadLength, frames[0].payloadLength)
        assertEquals(12, frames[1].payload.size, "control frames are exact")
        assertTrue(FrameCodec.encode(frames[0]).contentEquals(FrameCodec.encode(video)))
    }
}
