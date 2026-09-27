package dev.ginga.receiver.ui

import dev.ginga.receiver.R
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AppearanceTest {
    @Test
    fun storageValuesRoundTrip() {
        for (appearance in Appearance.entries) assertEquals(appearance, Appearance.fromStorage(appearance.storageValue))
        // The values are persisted: they must never change.
        assertEquals(listOf("system", "light", "dark", "space"), Appearance.entries.map { it.storageValue })
    }

    @Test
    fun unknownOrMissingValuesFollowTheSystem() {
        assertEquals(Appearance.SYSTEM, Appearance.fromStorage(null))
        assertEquals(Appearance.SYSTEM, Appearance.fromStorage(""))
        assertEquals(Appearance.SYSTEM, Appearance.fromStorage("SPACE"))
    }

    @Test
    fun eachAppearanceHasItsTheme() {
        assertEquals(R.style.Theme_Ginga_System, Appearance.SYSTEM.themeRes)
        assertEquals(R.style.Theme_Ginga_Light, Appearance.LIGHT.themeRes)
        assertEquals(R.style.Theme_Ginga_Dark, Appearance.DARK.themeRes)
        assertEquals(R.style.Theme_Ginga_Space, Appearance.SPACE.themeRes)
        assertEquals(4, Appearance.entries.map { it.themeRes }.toSet().size)
    }

    @Test
    fun onlySpaceBlackIsPureBlack() {
        assertTrue(Appearance.SPACE.pureBlack)
        assertFalse(Appearance.DARK.pureBlack)
        assertFalse(Appearance.SYSTEM.pureBlack)
    }
}
