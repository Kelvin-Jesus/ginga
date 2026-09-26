package dev.tab2mac.input

import android.view.InputDevice
import android.view.KeyEvent

/**
 * Forwards a hardware keyboard attached to the tablet (§3.3c). Only physical, alphabetic
 * keyboards are captured; Back, volume and the navigation keys of the tablet itself keep working.
 * Keys without a HID usage (the DeX key) stay with Android. Held keys are remembered so they can
 * be released when the window loses focus ([releaseAll]); no allocation per key.
 *
 * @param send forwards one key; false when nothing takes it (no stream, or a Mac without
 *   `keyboard`), and the event then stays with Android. UI thread.
 */
class KeyboardCapture(private val send: (down: Boolean, usage: Int, modifiers: Int, eventTimeNanos: Long) -> Boolean) {
    private val held = BooleanArray(256)
    private var modifiers = 0

    /** From `Activity.dispatchKeyEvent`: true when the event was forwarded (consume it). */
    fun onKeyEvent(event: KeyEvent): Boolean {
        val down = when (event.action) {
            KeyEvent.ACTION_DOWN -> true
            KeyEvent.ACTION_UP -> false
            else -> return false
        }
        return onKey(event.keyCode, event.scanCode, event.metaState, down, isHardwareKeyboard(event), event.eventTime * 1_000_000L)
    }

    /** The pure part of [onKeyEvent]. */
    fun onKey(keyCode: Int, scanCode: Int, metaState: Int, down: Boolean, fromHardwareKeyboard: Boolean, eventTimeNanos: Long): Boolean {
        if (!fromHardwareKeyboard) return false
        val usage = HidKeyboard.usage(keyCode, scanCode)
        if (usage == HidKeyboard.NONE || usage >= held.size) return false
        if (!down && !held[usage]) return false // its down went to Android
        val state = HidKeyboard.modifiers(metaState, usage, down)
        if (!send(down, usage, state, eventTimeNanos)) {
            if (!down) held[usage] = false
            return false
        }
        held[usage] = down
        modifiers = state
        return true
    }

    /** Lifts every key still held (the window lost focus, or the stream screen went away). */
    fun releaseAll(eventTimeNanos: Long) {
        for (usage in held.indices) {
            if (!held[usage]) continue
            held[usage] = false
            modifiers = modifiers and HidKeyboard.modifierBit(usage).inv()
            send(false, usage, modifiers, eventTimeNanos)
        }
    }

    private fun isHardwareKeyboard(event: KeyEvent): Boolean {
        val device = event.device ?: return false
        return !device.isVirtual &&
            device.keyboardType == InputDevice.KEYBOARD_TYPE_ALPHABETIC &&
            event.isFromSource(InputDevice.SOURCE_KEYBOARD)
    }
}
