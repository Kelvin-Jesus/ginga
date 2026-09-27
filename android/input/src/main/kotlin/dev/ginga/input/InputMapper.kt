package dev.ginga.input

import dev.ginga.protocol.InputAction
import dev.ginga.protocol.InputKind
import dev.ginga.protocol.InputMessage
import dev.ginga.protocol.PointerButtons
import dev.ginga.protocol.PointerRecord
import dev.ginga.protocol.ToolType
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Turns [MotionSample]s into protocol INPUT messages (§3.3). Pure and stateful (gesture and
 * hover tracking, sequence numbers); one instance per input surface, used from one thread.
 *
 * - Coordinates are normalised to 0…65535 across [videoRect] — the rendered video, not the view,
 *   so letterbox bars don't skew them. Points outside are clamped to the edge.
 * - A gesture that starts outside the video (on a letterbox bar) is ignored entirely.
 * - For POINTER_DOWN / POINTER_UP the pointer that changed comes first in the record list.
 * - Hover reports pressure 0; a HOVER_MOVE without a preceding HOVER_ENTER is sent as HOVER_ENTER.
 * - Button changes (e.g. the S Pen side button) are sent as MOVE, or HOVER_MOVE while hovering.
 */
class InputMapper {
    /** The video's rectangle in the input view's coordinates; nothing is sent while null or empty. */
    @Volatile
    var videoRect: NormalizationRect? = null

    private var nextSequence = 0L
    private var gesture = Gesture.IDLE
    private var hovering = false

    private enum class Gesture { IDLE, ACTIVE, REJECTED }

    /** The INPUT message for [sample], or null when nothing should be sent. */
    fun map(sample: MotionSample): InputMessage? {
        val rect = videoRect?.takeUnless { it.isEmpty } ?: return null
        if (sample.pointers.isEmpty()) return null
        val action = protocolAction(sample, rect) ?: return null
        val hover = action == InputAction.HOVER_ENTER || action == InputAction.HOVER_MOVE || action == InputAction.HOVER_EXIT
        val ordered = actionPointerFirst(sample, action)
        val message = InputMessage(
            sequence = nextSequence,
            eventTimeUs = sample.eventTimeNanos / 1_000,
            kind = kindOf(ordered.first().tool),
            action = action,
            pointers = ordered.take(MAX_POINTERS).map { record(it, rect, sample.buttons, hover) },
        )
        nextSequence = (nextSequence + 1) and 0xFFFF_FFFFL
        return message
    }

    /** Forgets gesture and hover state, e.g. when the stream restarts. */
    fun reset() {
        gesture = Gesture.IDLE
        hovering = false
    }

    private fun protocolAction(sample: MotionSample, rect: NormalizationRect): InputAction? = when (sample.action) {
        PointerAction.DOWN -> {
            val first = sample.pointers.first()
            if (rect.contains(first.x, first.y)) {
                gesture = Gesture.ACTIVE
                hovering = false
                InputAction.DOWN
            } else {
                gesture = Gesture.REJECTED
                null
            }
        }
        PointerAction.POINTER_DOWN -> InputAction.POINTER_DOWN.takeIf { gesture == Gesture.ACTIVE }
        PointerAction.MOVE -> InputAction.MOVE.takeIf { gesture == Gesture.ACTIVE }
        PointerAction.POINTER_UP -> InputAction.POINTER_UP.takeIf { gesture == Gesture.ACTIVE }
        PointerAction.UP, PointerAction.CANCEL -> {
            val wasActive = gesture == Gesture.ACTIVE
            gesture = Gesture.IDLE
            if (!wasActive) null else if (sample.action == PointerAction.UP) InputAction.UP else InputAction.CANCEL
        }
        PointerAction.HOVER_ENTER -> {
            hovering = true
            InputAction.HOVER_ENTER
        }
        PointerAction.HOVER_MOVE -> if (hovering) {
            InputAction.HOVER_MOVE
        } else {
            hovering = true
            InputAction.HOVER_ENTER
        }
        PointerAction.HOVER_EXIT -> if (hovering) {
            hovering = false
            InputAction.HOVER_EXIT
        } else {
            null
        }
        PointerAction.BUTTON_PRESS, PointerAction.BUTTON_RELEASE -> when {
            gesture == Gesture.ACTIVE -> InputAction.MOVE
            hovering -> InputAction.HOVER_MOVE
            else -> null
        }
        PointerAction.OTHER -> null
    }

    private fun actionPointerFirst(sample: MotionSample, action: InputAction): List<PointerSample> {
        val index = sample.actionIndex
        if ((action != InputAction.POINTER_DOWN && action != InputAction.POINTER_UP) || index !in sample.pointers.indices || index == 0) {
            return sample.pointers
        }
        return listOf(sample.pointers[index]) + sample.pointers.filterIndexed { i, _ -> i != index }
    }

    private fun record(pointer: PointerSample, rect: NormalizationRect, buttons: PointerButtons, hover: Boolean): PointerRecord {
        val pen = pointer.tool == PointerTool.STYLUS || pointer.tool == PointerTool.ERASER
        val pressure = when {
            hover -> 0f
            pointer.tool == PointerTool.FINGER || pointer.tool == PointerTool.UNKNOWN ->
                if (pointer.pressure > 0f) pointer.pressure else 1f // some panels report 0 for touches
            else -> pointer.pressure
        }
        val (tiltX, tiltY) = if (pen) Tilt.toProtocol(pointer.tiltRadians, pointer.orientationRadians) else 0 to 0
        return PointerRecord(
            pointerId = pointer.pointerId.coerceIn(0, 0xFF),
            toolType = toolType(pointer.tool),
            buttons = buttons,
            x = normalize((pointer.x - rect.left) / rect.width),
            y = normalize((pointer.y - rect.top) / rect.height),
            pressure = normalize(pressure),
            tiltX = tiltX,
            tiltY = tiltY,
            distance = if (pen) pointer.distance.roundToInt().coerceIn(0, 0xFFFF) else 0,
        )
    }

    companion object {
        /** The protocol's u8 pointerCount. */
        const val MAX_POINTERS: Int = 255

        /** 0…1 → 0…65535, clamped. */
        fun normalize(fraction: Float): Int =
            if (fraction.isNaN()) 0 else (fraction.coerceIn(0f, 1f) * PointerRecord.MAX_NORMALIZED).roundToInt()

        fun toolType(tool: PointerTool): ToolType = when (tool) {
            PointerTool.FINGER -> ToolType.FINGER
            PointerTool.STYLUS -> ToolType.STYLUS
            PointerTool.ERASER -> ToolType.ERASER
            PointerTool.MOUSE -> ToolType.MOUSE
            PointerTool.UNKNOWN, PointerTool.PALM -> ToolType.UNKNOWN
        }

        fun kindOf(tool: PointerTool): InputKind = when (tool) {
            PointerTool.STYLUS, PointerTool.ERASER -> InputKind.STYLUS
            PointerTool.MOUSE -> InputKind.MOUSE
            else -> InputKind.TOUCH
        }
    }
}

/**
 * Stylus tilt: Android's polar `AXIS_TILT` + `AXIS_ORIENTATION` → the protocol's tiltX/tiltY,
 * using the W3C Pointer Events convention (as Chromium does on Android): positive tiltX leans the
 * pen's top end towards +x (right), positive tiltY towards +y (down, towards the user).
 */
object Tilt {
    /** (tiltX°, tiltY°), each in −90…90. */
    fun degrees(tiltRadians: Float, orientationRadians: Float): Pair<Double, Double> {
        val tilt = tiltRadians.toDouble().takeUnless { it.isNaN() }?.coerceIn(0.0, PI / 2) ?: 0.0
        val orientation = orientationRadians.toDouble().takeUnless { it.isNaN() } ?: 0.0
        val radius = sin(tilt)
        val z = cos(tilt)
        val x = atan2(sin(-orientation) * radius, z)
        val y = atan2(cos(-orientation) * radius, z)
        return Math.toDegrees(x) to Math.toDegrees(y)
    }

    /** Degrees → −32767…32767 (§3.3), rounding half away from zero so ±angles stay symmetric. */
    fun fromDegrees(degrees: Double): Int {
        if (degrees.isNaN()) return 0
        val scaled = abs(degrees) / 90.0 * PointerRecord.MAX_TILT
        val magnitude = floor(scaled + 0.5).coerceAtMost(PointerRecord.MAX_TILT.toDouble()).toInt()
        return if (degrees < 0) -magnitude else magnitude
    }

    /** Protocol (tiltX, tiltY). */
    fun toProtocol(tiltRadians: Float, orientationRadians: Float): Pair<Int, Int> {
        val (x, y) = degrees(tiltRadians, orientationRadians)
        return fromDegrees(x) to fromDegrees(y)
    }
}
