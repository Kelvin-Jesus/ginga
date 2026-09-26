package dev.tab2mac.input

import android.view.KeyEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HidKeyboardTest {
    // Linux evdev scan codes, as KeyEvent.getScanCode reports them.
    private val scanA = 30
    private val scanLeftShift = 42

    @Test
    fun lettersDigitsAndPunctuationByScanCode() {
        assertEquals(0x04, HidKeyboard.usage(KeyEvent.KEYCODE_A, scanA))
        assertEquals(0x1D, HidKeyboard.usage(KeyEvent.KEYCODE_Z, 44))
        assertEquals(0x14, HidKeyboard.usage(KeyEvent.KEYCODE_Q, 16))
        assertEquals(0x1E, HidKeyboard.usage(KeyEvent.KEYCODE_1, 2))
        assertEquals(0x27, HidKeyboard.usage(KeyEvent.KEYCODE_0, 11))
        assertEquals(0x2D, HidKeyboard.usage(KeyEvent.KEYCODE_MINUS, 12))
        assertEquals(0x33, HidKeyboard.usage(KeyEvent.KEYCODE_SEMICOLON, 39)) // ABNT2: ç
        assertEquals(0x38, HidKeyboard.usage(KeyEvent.KEYCODE_SLASH, 53))
    }

    @Test
    fun abnt2ExtraKeys() {
        assertEquals(0x87, HidKeyboard.usage(KeyEvent.KEYCODE_RO, 89), "International1, / ? next to right shift")
        assertEquals(0x64, HidKeyboard.usage(KeyEvent.KEYCODE_BACKSLASH, 86), "Non-US \\ left of Z")
        assertEquals(0x31, HidKeyboard.usage(KeyEvent.KEYCODE_BACKSLASH, 43))
        assertEquals(0x85, HidKeyboard.usage(KeyEvent.KEYCODE_NUMPAD_COMMA, 121))
    }

    @Test
    fun navigationFunctionAndEditingKeys() {
        assertEquals(0x3A, HidKeyboard.usage(KeyEvent.KEYCODE_F1, 59))
        assertEquals(0x45, HidKeyboard.usage(KeyEvent.KEYCODE_F12, 88))
        assertEquals(0x52, HidKeyboard.usage(KeyEvent.KEYCODE_DPAD_UP, 103))
        assertEquals(0x50, HidKeyboard.usage(KeyEvent.KEYCODE_DPAD_LEFT, 105))
        assertEquals(0x4A, HidKeyboard.usage(KeyEvent.KEYCODE_MOVE_HOME, 102))
        assertEquals(0x4D, HidKeyboard.usage(KeyEvent.KEYCODE_MOVE_END, 107))
        assertEquals(0x4B, HidKeyboard.usage(KeyEvent.KEYCODE_PAGE_UP, 104))
        assertEquals(0x4E, HidKeyboard.usage(KeyEvent.KEYCODE_PAGE_DOWN, 109))
        assertEquals(0x4C, HidKeyboard.usage(KeyEvent.KEYCODE_FORWARD_DEL, 111))
        assertEquals(0x49, HidKeyboard.usage(KeyEvent.KEYCODE_INSERT, 110))
        assertEquals(0x29, HidKeyboard.usage(KeyEvent.KEYCODE_ESCAPE, 1))
        assertEquals(0x2B, HidKeyboard.usage(KeyEvent.KEYCODE_TAB, 15))
        assertEquals(0x28, HidKeyboard.usage(KeyEvent.KEYCODE_ENTER, 28))
        assertEquals(0x2A, HidKeyboard.usage(KeyEvent.KEYCODE_DEL, 14))
        assertEquals(0x2C, HidKeyboard.usage(KeyEvent.KEYCODE_SPACE, 57))
        assertEquals(0x5F, HidKeyboard.usage(KeyEvent.KEYCODE_NUMPAD_7, 71))
        assertEquals(0x58, HidKeyboard.usage(KeyEvent.KEYCODE_NUMPAD_ENTER, 96))
    }

    @Test
    fun modifiersAreKeysToo() {
        assertEquals(0xE0, HidKeyboard.usage(KeyEvent.KEYCODE_CTRL_LEFT, 29))
        assertEquals(0xE1, HidKeyboard.usage(KeyEvent.KEYCODE_SHIFT_LEFT, scanLeftShift))
        assertEquals(0xE2, HidKeyboard.usage(KeyEvent.KEYCODE_ALT_LEFT, 56))
        assertEquals(0xE3, HidKeyboard.usage(KeyEvent.KEYCODE_META_LEFT, 125), "⊞ / Samsung key → left meta")
        assertEquals(0xE6, HidKeyboard.usage(KeyEvent.KEYCODE_ALT_RIGHT, 100))
        assertEquals(0xE7, HidKeyboard.usage(KeyEvent.KEYCODE_META_RIGHT, 126))
    }

    @Test
    fun keyCodesStandInWithoutAScanCode() {
        assertEquals(0x04, HidKeyboard.usage(KeyEvent.KEYCODE_A, 0))
        assertEquals(0xE3, HidKeyboard.usage(KeyEvent.KEYCODE_META_LEFT, 0))
        assertEquals(0x52, HidKeyboard.usage(KeyEvent.KEYCODE_DPAD_UP, 0))
        assertEquals(0x87, HidKeyboard.usage(KeyEvent.KEYCODE_RO, 0))
    }

    @Test
    fun androidOnlyKeysHaveNoUsage() {
        assertEquals(HidKeyboard.NONE, HidKeyboard.usage(KeyEvent.KEYCODE_BACK, 0))
        assertEquals(HidKeyboard.NONE, HidKeyboard.usage(KeyEvent.KEYCODE_VOLUME_UP, 0))
        assertEquals(HidKeyboard.NONE, HidKeyboard.usage(KeyEvent.KEYCODE_HOME, 0))
        assertEquals(HidKeyboard.NONE, HidKeyboard.usage(9999, 0))
        assertEquals(HidKeyboard.NONE, HidKeyboard.usage(0, 250))
    }

    @Test
    fun modifierStateIsTheStateAfterTheEvent() {
        val shift = KeyEvent.META_SHIFT_ON or KeyEvent.META_SHIFT_LEFT_ON
        assertEquals(0x02, HidKeyboard.modifiers(0, 0xE1, down = true), "own key forced down")
        assertEquals(0x00, HidKeyboard.modifiers(shift, 0xE1, down = false), "own key forced up")
        assertEquals(0x02, HidKeyboard.modifiers(shift, 0x04, down = true))
        val all = KeyEvent.META_CTRL_LEFT_ON or KeyEvent.META_ALT_LEFT_ON or KeyEvent.META_META_LEFT_ON or
            KeyEvent.META_CTRL_RIGHT_ON or KeyEvent.META_SHIFT_RIGHT_ON or KeyEvent.META_ALT_RIGHT_ON or
            KeyEvent.META_META_RIGHT_ON or KeyEvent.META_CAPS_LOCK_ON
        assertEquals(0x1FD, HidKeyboard.modifiers(all, 0x04, down = true))
    }

    @Test
    fun captureForwardsHardwareKeysAndRemembersHeldOnes() {
        val sent = mutableListOf<String>()
        var accepting = true
        val capture = KeyboardCapture { down, usage, modifiers, _ ->
            if (accepting) sent += "${if (down) "down" else "up"} %02x %03x".format(usage, modifiers)
            accepting
        }
        assertFalse(capture.onKey(KeyEvent.KEYCODE_BACK, 0, 0, down = true, fromHardwareKeyboard = false, eventTimeNanos = 0), "navigation keys stay")
        assertFalse(capture.onKey(KeyEvent.KEYCODE_A, scanA, 0, down = true, fromHardwareKeyboard = false, eventTimeNanos = 0), "on-screen keyboard stays")
        assertFalse(capture.onKey(KeyEvent.KEYCODE_HOME, 0, 0, down = true, fromHardwareKeyboard = true, eventTimeNanos = 0), "no HID usage: stays")

        assertTrue(capture.onKey(KeyEvent.KEYCODE_SHIFT_LEFT, scanLeftShift, 0, true, true, 1))
        assertTrue(capture.onKey(KeyEvent.KEYCODE_A, scanA, KeyEvent.META_SHIFT_LEFT_ON, true, true, 2))
        assertTrue(capture.onKey(KeyEvent.KEYCODE_A, scanA, KeyEvent.META_SHIFT_LEFT_ON, true, true, 3)) // repeat
        assertTrue(capture.onKey(KeyEvent.KEYCODE_A, scanA, KeyEvent.META_SHIFT_LEFT_ON, false, true, 4))
        capture.releaseAll(5) // focus lost with shift still down
        assertEquals(listOf("down e1 002", "down 04 002", "down 04 002", "up 04 002", "up e1 000"), sent)

        accepting = false
        assertFalse(capture.onKey(KeyEvent.KEYCODE_A, scanA, 0, true, true, 6), "no stream: Android keeps it")
        assertFalse(capture.onKey(KeyEvent.KEYCODE_A, scanA, 0, false, true, 7), "an up whose down wasn't sent stays too")
    }
}
