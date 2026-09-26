package dev.tab2mac.input

import android.view.KeyEvent

/**
 * Android keys → USB HID usages on the Keyboard/Keypad page 0x07 (PROTOCOL.md §3.3c). The
 * physical key is what counts, since the Mac applies its own layout: the Linux scan code
 * (`KeyEvent.getScanCode`, the evdev key the kernel saw) is used first, the Android key code only
 * when there is no known scan code (virtual keyboards, remapped devices). Pure tables, no
 * allocation per key.
 */
object HidKeyboard {
    /** No HID usage: the key isn't forwarded (for example the DeX key). */
    const val NONE: Int = 0

    const val LEFT_CONTROL: Int = 0xE0
    const val RIGHT_META: Int = 0xE7

    /** `modifiers` bit 8: caps lock is on. */
    const val CAPS_LOCK_BIT: Int = 1 shl 8

    /** Linux evdev key code → HID usage (the inverse of the kernel's `hid_keyboard` table). */
    private val SCAN = IntArray(200).apply {
        this[1] = 0x29 // Escape
        for (i in 0 until 9) this[2 + i] = 0x1E + i // 1…9
        this[11] = 0x27 // 0
        this[12] = 0x2D // - _
        this[13] = 0x2E // = +
        this[14] = 0x2A // Backspace
        this[15] = 0x2B // Tab
        "qwertyuiop".forEachIndexed { i, c -> this[16 + i] = letter(c) }
        this[26] = 0x2F // [ {
        this[27] = 0x30 // ] }
        this[28] = 0x28 // Enter
        this[29] = 0xE0 // left control
        "asdfghjkl".forEachIndexed { i, c -> this[30 + i] = letter(c) }
        this[39] = 0x33 // ; :   (ABNT2: ç)
        this[40] = 0x34 // ' "   (ABNT2: ~ ^)
        this[41] = 0x35 // ` ~   (ABNT2: ' ")
        this[42] = 0xE1 // left shift
        this[43] = 0x31 // \ |   (ISO/ABNT2: the key left of Enter, HID 0x32 also reads 43)
        "zxcvbnm".forEachIndexed { i, c -> this[44 + i] = letter(c) }
        this[51] = 0x36 // , <
        this[52] = 0x37 // . >
        this[53] = 0x38 // / ?   (ABNT2: ; :)
        this[54] = 0xE5 // right shift
        this[55] = 0x55 // keypad *
        this[56] = 0xE2 // left alt
        this[57] = 0x2C // space
        this[58] = 0x39 // Caps Lock
        for (i in 0 until 10) this[59 + i] = 0x3A + i // F1…F10
        this[69] = 0x53 // Num Lock
        this[70] = 0x47 // Scroll Lock
        this[71] = 0x5F // keypad 7
        this[72] = 0x60 // keypad 8
        this[73] = 0x61 // keypad 9
        this[74] = 0x56 // keypad -
        this[75] = 0x5C // keypad 4
        this[76] = 0x5D // keypad 5
        this[77] = 0x5E // keypad 6
        this[78] = 0x57 // keypad +
        this[79] = 0x59 // keypad 1
        this[80] = 0x5A // keypad 2
        this[81] = 0x5B // keypad 3
        this[82] = 0x62 // keypad 0
        this[83] = 0x63 // keypad .
        this[86] = 0x64 // ISO key left of Z: Non-US \ |  (ABNT2: \ |)
        this[87] = 0x44 // F11
        this[88] = 0x45 // F12
        this[89] = 0x87 // ABNT2 / JIS: International1 (/ ?)
        this[96] = 0x58 // keypad Enter
        this[97] = 0xE4 // right control
        this[98] = 0x54 // keypad /
        this[99] = 0x46 // Print Screen
        this[100] = 0xE6 // right alt (AltGr)
        this[102] = 0x4A // Home
        this[103] = 0x52 // Up
        this[104] = 0x4B // Page Up
        this[105] = 0x50 // Left
        this[106] = 0x4F // Right
        this[107] = 0x4D // End
        this[108] = 0x51 // Down
        this[109] = 0x4E // Page Down
        this[110] = 0x49 // Insert
        this[111] = 0x4C // Delete
        this[117] = 0x67 // keypad =
        this[119] = 0x48 // Pause
        this[121] = 0x85 // keypad , (ABNT2 keypad .)
        this[124] = 0x89 // International3 (Yen)
        this[125] = 0xE3 // left meta (⊞ / Samsung key)
        this[126] = 0xE7 // right meta
        this[127] = 0x65 // Application (Menu)
        for (i in 0 until 12) this[183 + i] = 0x68 + i // F13…F24
    }

    /** Android key code → HID usage, for keys without a known scan code. */
    private val KEYCODE = IntArray(KeyEvent.KEYCODE_RO + 1).apply {
        for (c in 'a'..'z') this[KeyEvent.KEYCODE_A + (c - 'a')] = letter(c)
        for (i in 1..9) this[KeyEvent.KEYCODE_0 + i] = 0x1E + i - 1
        this[KeyEvent.KEYCODE_0] = 0x27
        this[KeyEvent.KEYCODE_ESCAPE] = 0x29
        this[KeyEvent.KEYCODE_MINUS] = 0x2D
        this[KeyEvent.KEYCODE_EQUALS] = 0x2E
        this[KeyEvent.KEYCODE_DEL] = 0x2A
        this[KeyEvent.KEYCODE_TAB] = 0x2B
        this[KeyEvent.KEYCODE_LEFT_BRACKET] = 0x2F
        this[KeyEvent.KEYCODE_RIGHT_BRACKET] = 0x30
        this[KeyEvent.KEYCODE_ENTER] = 0x28
        this[KeyEvent.KEYCODE_SEMICOLON] = 0x33
        this[KeyEvent.KEYCODE_APOSTROPHE] = 0x34
        this[KeyEvent.KEYCODE_GRAVE] = 0x35
        this[KeyEvent.KEYCODE_BACKSLASH] = 0x31
        this[KeyEvent.KEYCODE_COMMA] = 0x36
        this[KeyEvent.KEYCODE_PERIOD] = 0x37
        this[KeyEvent.KEYCODE_SLASH] = 0x38
        this[KeyEvent.KEYCODE_SPACE] = 0x2C
        this[KeyEvent.KEYCODE_CAPS_LOCK] = 0x39
        for (i in 0 until 12) this[KeyEvent.KEYCODE_F1 + i] = 0x3A + i
        this[KeyEvent.KEYCODE_SYSRQ] = 0x46
        this[KeyEvent.KEYCODE_SCROLL_LOCK] = 0x47
        this[KeyEvent.KEYCODE_BREAK] = 0x48
        this[KeyEvent.KEYCODE_INSERT] = 0x49
        this[KeyEvent.KEYCODE_MOVE_HOME] = 0x4A
        this[KeyEvent.KEYCODE_PAGE_UP] = 0x4B
        this[KeyEvent.KEYCODE_FORWARD_DEL] = 0x4C
        this[KeyEvent.KEYCODE_MOVE_END] = 0x4D
        this[KeyEvent.KEYCODE_PAGE_DOWN] = 0x4E
        this[KeyEvent.KEYCODE_DPAD_RIGHT] = 0x4F
        this[KeyEvent.KEYCODE_DPAD_LEFT] = 0x50
        this[KeyEvent.KEYCODE_DPAD_DOWN] = 0x51
        this[KeyEvent.KEYCODE_DPAD_UP] = 0x52
        this[KeyEvent.KEYCODE_NUM_LOCK] = 0x53
        this[KeyEvent.KEYCODE_NUMPAD_DIVIDE] = 0x54
        this[KeyEvent.KEYCODE_NUMPAD_MULTIPLY] = 0x55
        this[KeyEvent.KEYCODE_NUMPAD_SUBTRACT] = 0x56
        this[KeyEvent.KEYCODE_NUMPAD_ADD] = 0x57
        this[KeyEvent.KEYCODE_NUMPAD_ENTER] = 0x58
        for (i in 1..9) this[KeyEvent.KEYCODE_NUMPAD_0 + i] = 0x59 + i - 1
        this[KeyEvent.KEYCODE_NUMPAD_0] = 0x62
        this[KeyEvent.KEYCODE_NUMPAD_DOT] = 0x63
        this[KeyEvent.KEYCODE_NUMPAD_EQUALS] = 0x67
        this[KeyEvent.KEYCODE_NUMPAD_COMMA] = 0x85
        this[KeyEvent.KEYCODE_MENU] = 0x65
        this[KeyEvent.KEYCODE_RO] = 0x87
        this[KeyEvent.KEYCODE_YEN] = 0x89
        this[KeyEvent.KEYCODE_CTRL_LEFT] = 0xE0
        this[KeyEvent.KEYCODE_SHIFT_LEFT] = 0xE1
        this[KeyEvent.KEYCODE_ALT_LEFT] = 0xE2
        this[KeyEvent.KEYCODE_META_LEFT] = 0xE3
        this[KeyEvent.KEYCODE_CTRL_RIGHT] = 0xE4
        this[KeyEvent.KEYCODE_SHIFT_RIGHT] = 0xE5
        this[KeyEvent.KEYCODE_ALT_RIGHT] = 0xE6
        this[KeyEvent.KEYCODE_META_RIGHT] = 0xE7
    }

    /** The HID usage of a key, or [NONE]. */
    fun usage(keyCode: Int, scanCode: Int): Int {
        if (scanCode in 1 until SCAN.size) {
            val byScan = SCAN[scanCode]
            if (byScan != NONE) return byScan
        }
        return if (keyCode in KEYCODE.indices) KEYCODE[keyCode] else NONE
    }

    /** The `modifiers` bit of a modifier key (usage 0xE0–0xE7), 0 for any other key. */
    fun modifierBit(usage: Int): Int = if (usage in LEFT_CONTROL..RIGHT_META) 1 shl (usage - LEFT_CONTROL) else 0

    /**
     * `modifiers` after an event (§3.3c): Android's meta state, with the event's own modifier key
     * forced down or up (the meta state of a modifier's own event isn't consistent across
     * devices).
     */
    fun modifiers(metaState: Int, usage: Int, down: Boolean): Int {
        var bits = 0
        if (metaState and KeyEvent.META_CTRL_LEFT_ON != 0) bits = bits or 0x01
        if (metaState and KeyEvent.META_SHIFT_LEFT_ON != 0) bits = bits or 0x02
        if (metaState and KeyEvent.META_ALT_LEFT_ON != 0) bits = bits or 0x04
        if (metaState and KeyEvent.META_META_LEFT_ON != 0) bits = bits or 0x08
        if (metaState and KeyEvent.META_CTRL_RIGHT_ON != 0) bits = bits or 0x10
        if (metaState and KeyEvent.META_SHIFT_RIGHT_ON != 0) bits = bits or 0x20
        if (metaState and KeyEvent.META_ALT_RIGHT_ON != 0) bits = bits or 0x40
        if (metaState and KeyEvent.META_META_RIGHT_ON != 0) bits = bits or 0x80
        if (metaState and KeyEvent.META_CAPS_LOCK_ON != 0) bits = bits or CAPS_LOCK_BIT
        val own = modifierBit(usage)
        return if (own == 0) bits else if (down) bits or own else bits and own.inv()
    }

    private fun letter(c: Char): Int = 0x04 + (c - 'a')
}
