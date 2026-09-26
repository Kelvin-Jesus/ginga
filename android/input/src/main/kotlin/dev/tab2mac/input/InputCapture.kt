package dev.tab2mac.input

import android.annotation.SuppressLint
import android.os.Build
import android.util.Log
import android.view.InputDevice
import android.view.MotionEvent
import android.view.PointerIcon
import android.view.View
import dev.tab2mac.protocol.InputMessage
import dev.tab2mac.protocol.PointerButtons

/**
 * `MotionEvent` → [MotionSample]s, including the historical (batched) samples of a move, oldest
 * first. The same sample objects are refilled for every call, so capturing input creates no
 * per-sample garbage besides the protocol messages themselves. Main thread only.
 */
class MotionEventAdapter {
    private val pointers = ArrayList<PointerSample>(MAX_POINTERS)
    private val spare = ArrayList<PointerSample>(MAX_POINTERS)
    private val sample = MotionSample(PointerAction.OTHER, 0, 0, PointerButtons.NONE, pointers)

    @PublishedApi
    internal val swipe = TouchpadSwipe()

    /**
     * Calls [onSample] for every historical sample, then for the current one. Touchpad gestures
     * are translated: a two-finger swipe becomes a two-finger touch (scrolling), other gestures
     * are dropped.
     */
    inline fun forEachSample(event: MotionEvent, onSample: (MotionSample) -> Unit) {
        when (AndroidInputMapping.touchpadGesture(event.classification)) {
            TouchpadGesture.IGNORED -> return
            TouchpadGesture.TWO_FINGER_SWIPE -> {
                forEachRawSample(event) { swipe.expand(it, onSample) }
                return
            }
            TouchpadGesture.NONE -> forEachRawSample(event, onSample)
        }
    }

    @PublishedApi
    internal inline fun forEachRawSample(event: MotionEvent, onSample: (MotionSample) -> Unit) {
        val action = AndroidInputMapping.action(event.actionMasked, event.flags)
        val buttons = AndroidInputMapping.buttons(event.buttonState)
        if (action == PointerAction.MOVE || action == PointerAction.HOVER_MOVE) {
            for (position in 0 until event.historySize) onSample(fill(event, action, buttons, position))
        }
        onSample(fill(event, action, buttons, CURRENT))
    }

    /** Refills the shared sample from [event] at history [position] ([CURRENT] for the event itself). */
    @PublishedApi
    internal fun fill(event: MotionEvent, action: PointerAction, buttons: PointerButtons, position: Int): MotionSample {
        val count = minOf(event.pointerCount, MAX_POINTERS)
        while (pointers.size > count) spare += pointers.removeAt(pointers.size - 1)
        while (pointers.size < count) pointers += spare.removeLastOrNull() ?: PointerSample(0, PointerTool.UNKNOWN, 0f, 0f)
        val fromMouse = event.isFromSource(InputDevice.SOURCE_MOUSE)
        for (index in 0 until count) {
            val pointer = pointers[index]
            pointer.pointerId = event.getPointerId(index)
            pointer.tool = AndroidInputMapping.tool(event.getToolType(index), fromMouse)
            if (position == CURRENT) {
                pointer.x = event.getX(index)
                pointer.y = event.getY(index)
                pointer.pressure = event.getPressure(index)
                pointer.tiltRadians = event.getAxisValue(MotionEvent.AXIS_TILT, index)
                pointer.orientationRadians = event.getAxisValue(MotionEvent.AXIS_ORIENTATION, index)
                pointer.distance = event.getAxisValue(MotionEvent.AXIS_DISTANCE, index)
            } else {
                pointer.x = event.getHistoricalX(index, position)
                pointer.y = event.getHistoricalY(index, position)
                pointer.pressure = event.getHistoricalPressure(index, position)
                pointer.tiltRadians = event.getHistoricalAxisValue(MotionEvent.AXIS_TILT, index, position)
                pointer.orientationRadians = event.getHistoricalAxisValue(MotionEvent.AXIS_ORIENTATION, index, position)
                pointer.distance = event.getHistoricalAxisValue(MotionEvent.AXIS_DISTANCE, index, position)
            }
        }
        sample.action = action
        sample.actionIndex = if (position == CURRENT) event.actionIndex else 0
        sample.eventTimeNanos = if (position == CURRENT) eventTimeNanos(event) else historicalTimeNanos(event, position)
        sample.buttons = buttons
        return sample
    }

    /** §3.3: `getEventTimeNanos()` (API 34), else the millisecond time. Same clock as `System.nanoTime()`. */
    private fun eventTimeNanos(event: MotionEvent): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) event.eventTimeNanos else event.eventTime * 1_000_000

    private fun historicalTimeNanos(event: MotionEvent, position: Int): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            event.getHistoricalEventTimeNanos(position)
        } else {
            event.getHistoricalEventTime(position) * 1_000_000
        }

    companion object {
        /** History position meaning "the event's current values". */
        const val CURRENT: Int = -1

        /** More pointers than any panel reports. */
        const val MAX_POINTERS: Int = 32
    }
}

/**
 * Captures touch and S Pen input on [view] and hands protocol messages to [sink] on the main
 * thread, one batch per `MotionEvent` (its historical samples plus the current one), so the
 * transport sends each batch in a single write.
 *
 * Power: input keeps Android's default vsync-aligned batching. Only while the S Pen (or eraser)
 * touches the screen is unbuffered dispatch requested, for pen latency; it ends with the stroke.
 *
 * Touches arrive through `OnTouchListener`; hover and button events of pointer devices through
 * `OnGenericMotionListener` (the view must not be clickable, or hover is consumed first).
 */
class InputCapture(
    private val view: View,
    private val mapper: InputMapper,
    private val sink: (List<InputMessage>) -> Unit,
) {
    private val adapter = MotionEventAdapter()

    /** Starts listening. */
    @SuppressLint("ClickableViewAccessibility")
    fun attach() {
        // A touchpad or mouse moves the Mac's pointer, which the stream shows (in the video or as
        // the CURSOR overlay): Android's own arrow on top would be a second, wrong pointer.
        view.pointerIcon = PointerIcon.getSystemIcon(view.context, PointerIcon.TYPE_NULL)
        view.setOnTouchListener { v, event ->
            if (event.actionMasked == MotionEvent.ACTION_DOWN && isPen(event)) v.requestUnbufferedDispatch(event)
            dispatch(event)
            true
        }
        view.setOnGenericMotionListener { _, event ->
            if (event.isFromSource(InputDevice.SOURCE_CLASS_POINTER)) {
                dispatch(event)
                true
            } else {
                false
            }
        }
    }

    /** Stops listening. */
    fun detach() {
        view.pointerIcon = null
        view.setOnTouchListener(null)
        view.setOnGenericMotionListener(null)
        mapper.reset()
    }

    private fun dispatch(event: MotionEvent) {
        try {
            var batch: ArrayList<InputMessage>? = null
            adapter.forEachSample(event) { sample ->
                mapper.map(sample)?.let { message ->
                    (batch ?: ArrayList<InputMessage>(event.historySize + 1).also { batch = it }) += message
                }
            }
            batch?.let(sink)
        } catch (e: RuntimeException) {
            Log.w(TAG, "input.dropped error=\"${e.message}\"")
        }
    }

    private fun isPen(event: MotionEvent): Boolean {
        val tool = event.getToolType(event.actionIndex)
        return tool == MotionEvent.TOOL_TYPE_STYLUS || tool == MotionEvent.TOOL_TYPE_ERASER
    }

    private companion object {
        const val TAG = "T2M/input"
    }
}
