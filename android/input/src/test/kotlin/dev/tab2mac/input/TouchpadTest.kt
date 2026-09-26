package dev.tab2mac.input

import android.view.MotionEvent
import dev.tab2mac.protocol.InputAction
import dev.tab2mac.protocol.InputKind
import dev.tab2mac.protocol.PointerButtons
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/** The Book Cover Keyboard's touchpad: Android reports it as a mouse whose tool is a finger. */
class TouchpadTest {
    private val rect = NormalizationRect(0f, 0f, 2560f, 1600f)

    @Test
    fun aTouchpadIsAMouseNotATouch() {
        assertEquals(PointerTool.MOUSE, AndroidInputMapping.tool(MotionEvent.TOOL_TYPE_FINGER, fromMouse = true))
        assertEquals(PointerTool.MOUSE, AndroidInputMapping.tool(MotionEvent.TOOL_TYPE_UNKNOWN, fromMouse = true))
        assertEquals(PointerTool.FINGER, AndroidInputMapping.tool(MotionEvent.TOOL_TYPE_FINGER))
        // The S Pen stays a pen whatever the source says.
        assertEquals(PointerTool.STYLUS, AndroidInputMapping.tool(MotionEvent.TOOL_TYPE_STYLUS, fromMouse = true))
    }

    /** Moving a finger on the touchpad hovers: the Mac pointer must follow (it ignored touch hovers). */
    @Test
    fun touchpadMovesAreMouseHovers() {
        val mapper = InputMapper().apply { videoRect = rect }
        val pointer = PointerSample(0, PointerTool.MOUSE, 1280f, 800f)
        val message = assertNotNull(mapper.map(MotionSample(PointerAction.HOVER_MOVE, 0, 1, PointerButtons.NONE, mutableListOf(pointer))))
        assertEquals(InputKind.MOUSE, message.kind)
        assertEquals(InputAction.HOVER_ENTER, message.action)
    }

    @Test
    fun gesturesAreClassified() {
        assertEquals(TouchpadGesture.TWO_FINGER_SWIPE, AndroidInputMapping.touchpadGesture(3))
        assertEquals(TouchpadGesture.IGNORED, AndroidInputMapping.touchpadGesture(4))
        assertEquals(TouchpadGesture.IGNORED, AndroidInputMapping.touchpadGesture(5))
        assertEquals(TouchpadGesture.NONE, AndroidInputMapping.touchpadGesture(MotionEvent.CLASSIFICATION_NONE))
    }

    /** A two-finger swipe becomes the two-finger touch the Mac scrolls with, never a click-drag. */
    @Test
    fun aTwoFingerSwipeScrolls() {
        val swipe = TouchpadSwipe()
        val mapper = InputMapper().apply { videoRect = rect }
        val messages = mutableListOf<Pair<InputAction, Int>>()
        var kind: InputKind? = null
        fun feed(action: PointerAction, y: Float) {
            val fake = PointerSample(0, PointerTool.MOUSE, 1000f, y)
            swipe.expand(MotionSample(action, 0, 1, PointerButtons.NONE, mutableListOf(fake))) { sample ->
                mapper.map(sample)?.let {
                    messages += it.action to it.pointers.size
                    kind = it.kind
                }
            }
        }
        feed(PointerAction.DOWN, 500f)
        feed(PointerAction.MOVE, 560f)
        feed(PointerAction.UP, 600f)
        assertEquals(
            listOf(InputAction.DOWN to 1, InputAction.POINTER_DOWN to 2, InputAction.MOVE to 2, InputAction.UP to 2),
            messages,
        )
        assertEquals(InputKind.TOUCH, kind)
    }
}
