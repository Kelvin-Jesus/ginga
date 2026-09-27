package dev.ginga.transport

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class ReconnectPolicyTest {

    @Test
    fun doublesFrom250MsUpTo5Seconds() {
        val policy = ReconnectPolicy()
        assertEquals(listOf(250L, 500L, 1_000L, 2_000L, 4_000L, 5_000L, 5_000L), (1..7).map(policy::delayMs))
        assertEquals(5_000, policy.delayMs(1_000))
    }

    @Test
    fun honoursCustomParameters() {
        val policy = ReconnectPolicy(initialDelayMs = 100, maxDelayMs = 1_000, multiplier = 3.0)
        assertEquals(listOf(100L, 300L, 900L, 1_000L), (1..4).map(policy::delayMs))
        assertEquals(listOf(40L, 40L, 40L), (1..3).map(ReconnectPolicy(40, 40, 1.0)::delayMs))
    }

    @Test
    fun rejectsNonsense() {
        assertFailsWith<IllegalArgumentException> { ReconnectPolicy(initialDelayMs = 0) }
        assertFailsWith<IllegalArgumentException> { ReconnectPolicy(initialDelayMs = 500, maxDelayMs = 100) }
        assertFailsWith<IllegalArgumentException> { ReconnectPolicy(multiplier = 0.5) }
        assertFailsWith<IllegalArgumentException> { ReconnectPolicy().delayMs(0) }
    }

    @Test
    fun backoffGrowsWithFailuresAndResetsAfterAHealthyConnection() {
        val backoff = Backoff()
        assertEquals(listOf(250L, 500L, 1_000L), List(3) { backoff.nextDelayMs() })
        assertEquals(3, backoff.consecutiveFailures)
        backoff.reset()
        assertEquals(0, backoff.consecutiveFailures)
        assertEquals(250, backoff.nextDelayMs())
    }
}
