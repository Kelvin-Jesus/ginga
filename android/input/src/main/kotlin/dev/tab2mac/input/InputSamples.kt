package dev.tab2mac.input

import android.view.MotionEvent
import dev.tab2mac.protocol.PointerButtons

/** What happened, independent of `MotionEvent` constants. */
enum class PointerAction {
    DOWN,
    POINTER_DOWN,
    MOVE,
    POINTER_UP,
    UP,
    CANCEL,
    HOVER_ENTER,
    HOVER_MOVE,
    HOVER_EXIT,
    BUTTON_PRESS,
    BUTTON_RELEASE,
    OTHER,
}

/** The kind of pointer. */
enum class PointerTool { UNKNOWN, FINGER, STYLUS, ERASER, MOUSE, PALM }

/**
 * One pointer of a [MotionSample], in the coordinates of the view that received the event.
 * Mutable so the Android adapter can refill the same instances for every sample (no garbage per
 * touch sample); the mapper never keeps a reference.
 *
 * @property pressure normally 0…1.
 * @property tiltRadians `AXIS_TILT`: 0 = perpendicular to the screen, π/2 = flat.
 * @property orientationRadians `AXIS_ORIENTATION`: direction the stylus points, 0 = up,
 *   +π/2 = right, ±π = down.
 * @property distance `AXIS_DISTANCE`: hover distance in device units, 0 if unknown.
 */
data class PointerSample(
    var pointerId: Int,
    var tool: PointerTool,
    var x: Float,
    var y: Float,
    var pressure: Float = 0f,
    var tiltRadians: Float = 0f,
    var orientationRadians: Float = 0f,
    var distance: Float = 0f,
)

/**
 * A pure snapshot of one `MotionEvent` (or one of its historical samples). Refilled in place by
 * the Android adapter, like [PointerSample].
 *
 * @property actionIndex index in [pointers] of the pointer that went down/up (POINTER_DOWN/UP).
 * @property eventTimeNanos `CLOCK_MONOTONIC` — the same base as `System.nanoTime()` (§5).
 * @property buttons protocol button bits (see [AndroidInputMapping.buttons]).
 */
data class MotionSample(
    var action: PointerAction,
    var actionIndex: Int,
    var eventTimeNanos: Long,
    var buttons: PointerButtons,
    val pointers: MutableList<PointerSample>,
)

/** Where the video is drawn inside the view that receives input (letterboxing!). */
data class NormalizationRect(val left: Float, val top: Float, val width: Float, val height: Float) {
    val isEmpty: Boolean get() = width <= 0f || height <= 0f

    fun contains(x: Float, y: Float): Boolean = x >= left && x < left + width && y >= top && y < top + height
}

/** Android constants → the pure model. The constants are compile-time values, so this is JVM-testable. */
object AndroidInputMapping {

    /**
     * From `getActionMasked()` and `getFlags()`. A cancelled UP or POINTER_UP (`FLAG_CANCELED`: the
     * pointer was a palm, lifted mid-gesture) becomes CANCEL, which ends the whole gesture: the
     * protocol can't cancel a single pointer.
     */
    fun action(actionMasked: Int, flags: Int = 0): PointerAction = when (actionMasked) {
        MotionEvent.ACTION_DOWN -> PointerAction.DOWN
        MotionEvent.ACTION_POINTER_DOWN -> PointerAction.POINTER_DOWN
        MotionEvent.ACTION_MOVE -> PointerAction.MOVE
        MotionEvent.ACTION_POINTER_UP -> if (flags and MotionEvent.FLAG_CANCELED != 0) PointerAction.CANCEL else PointerAction.POINTER_UP
        MotionEvent.ACTION_UP -> if (flags and MotionEvent.FLAG_CANCELED != 0) PointerAction.CANCEL else PointerAction.UP
        MotionEvent.ACTION_CANCEL -> PointerAction.CANCEL
        MotionEvent.ACTION_HOVER_ENTER -> PointerAction.HOVER_ENTER
        MotionEvent.ACTION_HOVER_MOVE -> PointerAction.HOVER_MOVE
        MotionEvent.ACTION_HOVER_EXIT -> PointerAction.HOVER_EXIT
        MotionEvent.ACTION_BUTTON_PRESS -> PointerAction.BUTTON_PRESS
        MotionEvent.ACTION_BUTTON_RELEASE -> PointerAction.BUTTON_RELEASE
        else -> PointerAction.OTHER
    }

    /**
     * From `getToolType(pointerIndex)`. [fromMouse]: the event's source is a mouse, which is how
     * Android reports a touchpad (the Book Cover Keyboard's, with tool type FINGER): it is a
     * pointer that hovers and clicks, not a touch, so it goes to the Mac as a mouse.
     */
    fun tool(toolType: Int, fromMouse: Boolean = false): PointerTool = when (toolType) {
        MotionEvent.TOOL_TYPE_FINGER -> if (fromMouse) PointerTool.MOUSE else PointerTool.FINGER
        MotionEvent.TOOL_TYPE_STYLUS -> PointerTool.STYLUS
        MotionEvent.TOOL_TYPE_ERASER -> PointerTool.ERASER
        MotionEvent.TOOL_TYPE_MOUSE -> PointerTool.MOUSE
        TOOL_TYPE_PALM -> PointerTool.PALM
        else -> if (fromMouse) PointerTool.MOUSE else PointerTool.UNKNOWN
    }

    /** From `getClassification()`: what a touchpad gesture is (API 34 values; older ones never report them). */
    fun touchpadGesture(classification: Int): TouchpadGesture = when (classification) {
        CLASSIFICATION_TWO_FINGER_SWIPE -> TouchpadGesture.TWO_FINGER_SWIPE
        CLASSIFICATION_MULTI_FINGER_SWIPE, CLASSIFICATION_PINCH -> TouchpadGesture.IGNORED
        else -> TouchpadGesture.NONE
    }

    private const val CLASSIFICATION_TWO_FINGER_SWIPE = 3
    private const val CLASSIFICATION_MULTI_FINGER_SWIPE = 4
    private const val CLASSIFICATION_PINCH = 5

    /** `MotionEvent.TOOL_TYPE_PALM` is hidden from the SDK but reported by some touch panels. */
    private const val TOOL_TYPE_PALM = 5

    /**
     * From `getButtonState()`: primary/secondary, and the S Pen side button
     * (`BUTTON_STYLUS_PRIMARY`) as protocol bit 2.
     */
    fun buttons(buttonState: Int): PointerButtons {
        var bits = PointerButtons.NONE
        if (buttonState and MotionEvent.BUTTON_PRIMARY != 0) bits += PointerButtons.PRIMARY
        if (buttonState and MotionEvent.BUTTON_SECONDARY != 0) bits += PointerButtons.SECONDARY
        if (buttonState and MotionEvent.BUTTON_STYLUS_PRIMARY != 0) bits += PointerButtons.STYLUS_PRIMARY
        if (buttonState and MotionEvent.BUTTON_STYLUS_SECONDARY != 0) bits += PointerButtons.STYLUS_SECONDARY
        return bits
    }
}

/** Touchpad gestures Android turns into a fake finger (source mouse). */
enum class TouchpadGesture {
    /** Not a touchpad gesture. */
    NONE,

    /** Two fingers sliding: scrolling, sent as a two-finger touch the Mac scrolls with. */
    TWO_FINGER_SWIPE,

    /** Three/four-finger swipes and pinches: Android's own, never a drag on the Mac. */
    IGNORED,
}

/**
 * A two-finger touchpad swipe → the two-finger touch the Mac already turns into scrolling
 * (with momentum on release). Android reports the swipe as one fake finger moving from the
 * pointer's position; a second finger is added beside it. Pure, with its own sample objects.
 */
class TouchpadSwipe {
    private val first = PointerSample(0, PointerTool.FINGER, 0f, 0f, pressure = 1f)
    private val second = PointerSample(1, PointerTool.FINGER, 0f, 0f, pressure = 1f)
    private val pointers = ArrayList<PointerSample>(2)
    private val out = MotionSample(PointerAction.OTHER, 0, 0, PointerButtons.NONE, pointers)

    /** Calls [onSample] with the touch samples for one sample of the swipe. */
    inline fun expand(sample: MotionSample, onSample: (MotionSample) -> Unit) {
        val finger = sample.pointers.firstOrNull() ?: return
        when (sample.action) {
            PointerAction.DOWN -> {
                onSample(fill(sample, finger, PointerAction.DOWN, count = 1))
                onSample(fill(sample, finger, PointerAction.POINTER_DOWN, count = 2, actionIndex = 1))
            }
            PointerAction.MOVE -> onSample(fill(sample, finger, PointerAction.MOVE, count = 2))
            PointerAction.UP, PointerAction.CANCEL -> onSample(fill(sample, finger, PointerAction.UP, count = 2))
            else -> Unit
        }
    }

    @PublishedApi
    internal fun fill(sample: MotionSample, finger: PointerSample, action: PointerAction, count: Int, actionIndex: Int = 0): MotionSample {
        first.x = finger.x
        first.y = finger.y
        second.x = finger.x + SPREAD_PX
        second.y = finger.y
        pointers.clear()
        pointers += first
        if (count == 2) pointers += second
        out.action = action
        out.actionIndex = actionIndex
        out.eventTimeNanos = sample.eventTimeNanos
        out.buttons = PointerButtons.NONE
        return out
    }

    companion object {
        /** How far apart the two fingers are; only their common movement matters. */
        const val SPREAD_PX: Float = 48f
    }
}
