package dev.ginga.input

import android.view.MotionEvent
import dev.ginga.protocol.InputAction
import dev.ginga.protocol.InputKind
import dev.ginga.protocol.PointerButtons
import dev.ginga.protocol.ToolType
import kotlin.math.PI
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class InputMapperTest {
    /** A 1600×2560 portrait view showing a landscape 2560×1600 stream: 1600×1000 at y = 780. */
    private val letterboxed = NormalizationRect(0f, 780f, 1600f, 1000f)

    private fun mapper(rect: NormalizationRect = letterboxed) = InputMapper().apply { videoRect = rect }

    private fun finger(id: Int, x: Float, y: Float, pressure: Float = 0.8f) = PointerSample(id, PointerTool.FINGER, x, y, pressure)

    private fun sample(action: PointerAction, vararg pointers: PointerSample, actionIndex: Int = 0, timeNanos: Long = 5_000_000, buttons: PointerButtons = PointerButtons.NONE) =
        MotionSample(action, actionIndex, timeNanos, buttons, pointers.toMutableList())

    @Test
    fun normalisesAgainstTheVideoRectNotTheView() {
        val message = assertNotNull(mapper().map(sample(PointerAction.DOWN, finger(0, 800f, 1280f))))
        assertEquals(InputAction.DOWN, message.action)
        assertEquals(InputKind.TOUCH, message.kind)
        val pointer = message.pointers.single()
        assertEquals(32768, pointer.x)
        assertEquals(32768, pointer.y)
        assertEquals(ToolType.FINGER, pointer.toolType)
        assertEquals(5_000, message.eventTimeUs)
    }

    @Test
    fun cornersMapToTheExtremesAndOutsidePointsAreClamped() {
        val mapper = mapper()
        val down = assertNotNull(mapper.map(sample(PointerAction.DOWN, finger(0, 0f, 780f))))
        assertEquals(0 to 0, down.pointers.single().let { it.x to it.y })
        val move = assertNotNull(mapper.map(sample(PointerAction.MOVE, finger(0, 1700f, 2000f))))
        assertEquals(65535 to 65535, move.pointers.single().let { it.x to it.y })
    }

    @Test
    fun gesturesStartingOnTheLetterboxAreIgnored() {
        val mapper = mapper()
        assertNull(mapper.map(sample(PointerAction.DOWN, finger(0, 800f, 100f))))
        assertNull(mapper.map(sample(PointerAction.MOVE, finger(0, 800f, 1000f))))
        assertNull(mapper.map(sample(PointerAction.UP, finger(0, 800f, 1000f))))
        // The next gesture inside works again.
        assertNotNull(mapper.map(sample(PointerAction.DOWN, finger(0, 800f, 1000f))))
    }

    @Test
    fun sequenceIncreasesPerMessageAndWraps() {
        val mapper = mapper()
        val first = assertNotNull(mapper.map(sample(PointerAction.DOWN, finger(0, 10f, 800f))))
        val second = assertNotNull(mapper.map(sample(PointerAction.MOVE, finger(0, 11f, 800f))))
        assertEquals(first.sequence + 1, second.sequence)

        val field = InputMapper::class.java.getDeclaredField("nextSequence").apply { isAccessible = true }
        field.setLong(mapper, 0xFFFF_FFFFL)
        val last = assertNotNull(mapper.map(sample(PointerAction.MOVE, finger(0, 12f, 800f))))
        val wrapped = assertNotNull(mapper.map(sample(PointerAction.MOVE, finger(0, 13f, 800f))))
        assertEquals(0xFFFF_FFFFL, last.sequence)
        assertEquals(0, wrapped.sequence)
    }

    @Test
    fun theChangedPointerComesFirstForPointerDownAndUp() {
        val mapper = mapper()
        mapper.map(sample(PointerAction.DOWN, finger(0, 100f, 900f)))
        val pointerDown = assertNotNull(
            mapper.map(sample(PointerAction.POINTER_DOWN, finger(0, 100f, 900f), finger(1, 200f, 900f), actionIndex = 1)),
        )
        assertEquals(InputAction.POINTER_DOWN, pointerDown.action)
        assertEquals(listOf(1, 0), pointerDown.pointers.map { it.pointerId })

        val pointerUp = assertNotNull(
            mapper.map(sample(PointerAction.POINTER_UP, finger(0, 100f, 900f), finger(1, 200f, 900f), actionIndex = 0)),
        )
        assertEquals(listOf(0, 1), pointerUp.pointers.map { it.pointerId })
        assertEquals(InputAction.UP, assertNotNull(mapper.map(sample(PointerAction.UP, finger(1, 200f, 900f)))).action)
    }

    @Test
    fun touchesWithoutPressureReportFullPressure() {
        val message = assertNotNull(mapper().map(sample(PointerAction.DOWN, finger(0, 10f, 800f, pressure = 0f))))
        assertEquals(65535, message.pointers.single().pressure)
    }

    @Test
    fun stylusHoverCarriesTiltAndDistanceButNoPressure() {
        val mapper = mapper()
        val pen = PointerSample(0, PointerTool.STYLUS, 400f, 1030f, pressure = 0.3f, tiltRadians = (PI / 4).toFloat(), orientationRadians = 0f, distance = 12.4f)
        val enter = assertNotNull(mapper.map(sample(PointerAction.HOVER_ENTER, pen)))
        assertEquals(InputKind.STYLUS, enter.kind)
        assertEquals(InputAction.HOVER_ENTER, enter.action)
        val record = enter.pointers.single()
        assertEquals(ToolType.STYLUS, record.toolType)
        assertEquals(0, record.pressure)
        assertEquals(12, record.distance)
        assertEquals(0, record.tiltX)
        assertTrue(record.tiltY in 16383..16384, "45° ≈ 16383.5, got ${record.tiltY}")
        assertEquals(InputAction.HOVER_MOVE, assertNotNull(mapper.map(sample(PointerAction.HOVER_MOVE, pen))).action)
        assertEquals(InputAction.HOVER_EXIT, assertNotNull(mapper.map(sample(PointerAction.HOVER_EXIT, pen))).action)
        assertNull(mapper.map(sample(PointerAction.HOVER_EXIT, pen)), "no second exit")
    }

    @Test
    fun hoverMoveWithoutEnterBecomesEnter() {
        val pen = PointerSample(0, PointerTool.STYLUS, 400f, 1030f)
        assertEquals(InputAction.HOVER_ENTER, assertNotNull(mapper().map(sample(PointerAction.HOVER_MOVE, pen))).action)
    }

    @Test
    fun stylusContactUsesRealPressureButtonsAndEraser() {
        val mapper = mapper()
        val eraser = PointerSample(0, PointerTool.ERASER, 400f, 1030f, pressure = 0.5f)
        val down = assertNotNull(mapper.map(sample(PointerAction.DOWN, eraser, buttons = PointerButtons.STYLUS_PRIMARY)))
        val record = down.pointers.single()
        assertEquals(ToolType.ERASER, record.toolType)
        assertEquals(32768, record.pressure)
        assertEquals(PointerButtons.STYLUS_PRIMARY, record.buttons)
        assertEquals(InputKind.STYLUS, down.kind)
    }

    @Test
    fun buttonChangesAreSentAsMovesOrHoverMoves() {
        val mapper = mapper()
        val pen = PointerSample(0, PointerTool.STYLUS, 400f, 1030f)
        assertNull(mapper.map(sample(PointerAction.BUTTON_PRESS, pen)), "neither touching nor hovering")
        mapper.map(sample(PointerAction.HOVER_ENTER, pen))
        val hoverPress = assertNotNull(mapper.map(sample(PointerAction.BUTTON_PRESS, pen, buttons = PointerButtons.STYLUS_PRIMARY)))
        assertEquals(InputAction.HOVER_MOVE, hoverPress.action)
        assertEquals(PointerButtons.STYLUS_PRIMARY, hoverPress.pointers.single().buttons)
    }

    @Test
    fun aPalmLiftedMidGestureCancelsItAndTheRestIsIgnored() {
        val mapper = mapper()
        mapper.map(sample(PointerAction.DOWN, finger(0, 10f, 800f)))
        mapper.map(sample(PointerAction.POINTER_DOWN, finger(0, 10f, 800f), finger(1, 500f, 900f), actionIndex = 1))
        val palm = AndroidInputMapping.action(MotionEvent.ACTION_POINTER_UP, MotionEvent.FLAG_CANCELED)
        val cancel = assertNotNull(mapper.map(sample(palm, finger(0, 10f, 800f), finger(1, 500f, 900f), actionIndex = 1)))
        assertEquals(InputAction.CANCEL, cancel.action)
        assertNull(mapper.map(sample(PointerAction.MOVE, finger(0, 12f, 800f))))
        assertNull(mapper.map(sample(PointerAction.UP, finger(0, 12f, 800f))))
    }

    @Test
    fun cancelEndsTheGesture() {
        val mapper = mapper()
        mapper.map(sample(PointerAction.DOWN, finger(0, 10f, 800f)))
        assertEquals(InputAction.CANCEL, assertNotNull(mapper.map(sample(PointerAction.CANCEL, finger(0, 10f, 800f)))).action)
        assertNull(mapper.map(sample(PointerAction.MOVE, finger(0, 10f, 800f))))
    }

    @Test
    fun nothingIsSentWithoutAVideoRect() {
        assertNull(InputMapper().map(sample(PointerAction.DOWN, finger(0, 10f, 10f))))
        assertNull(mapper(NormalizationRect(0f, 0f, 0f, 0f)).map(sample(PointerAction.DOWN, finger(0, 10f, 10f))))
    }
}

class TiltTest {
    @Test
    fun perpendicularPenHasNoTilt() {
        assertEquals(0 to 0, Tilt.toProtocol(0f, 1.3f))
    }

    @Test
    fun followsThePointerEventsConvention() {
        // Pointing up (tip towards the top): the top end leans towards the user, +y.
        val (upX, upY) = Tilt.toProtocol((PI / 4).toFloat(), 0f)
        assertEquals(0, upX)
        assertTrue(upY in 16383..16384, "45° ≈ 16383.5, got $upY")
        // Pointing right: the top end leans left, −x.
        val (rightX, rightY) = Tilt.toProtocol((PI / 4).toFloat(), (PI / 2).toFloat())
        assertTrue(rightX in -16384..-16383, "−45° ≈ −16383.5, got $rightX")
        assertEquals(0, rightY)
        assertEquals(-Tilt.fromDegrees(30.0), Tilt.fromDegrees(-30.0))
        // A right-handed writer (pointing up-left) leans right and towards the user.
        val (x, y) = Tilt.toProtocol((PI / 4).toFloat(), (-PI / 4).toFloat())
        assertTrue(x > 0 && y > 0)
    }

    @Test
    fun flatPenReachesTheLimit() {
        assertEquals(0 to 32767, Tilt.toProtocol((PI / 2).toFloat(), 0f))
        assertEquals(32767, Tilt.fromDegrees(120.0))
        assertEquals(-32767, Tilt.fromDegrees(-95.0))
    }
}

class AndroidInputMappingTest {
    @Test
    fun mapsActions() {
        assertEquals(PointerAction.DOWN, AndroidInputMapping.action(MotionEvent.ACTION_DOWN))
        assertEquals(PointerAction.POINTER_UP, AndroidInputMapping.action(MotionEvent.ACTION_POINTER_UP))
        assertEquals(PointerAction.HOVER_MOVE, AndroidInputMapping.action(MotionEvent.ACTION_HOVER_MOVE))
        assertEquals(PointerAction.CANCEL, AndroidInputMapping.action(MotionEvent.ACTION_UP, MotionEvent.FLAG_CANCELED))
        assertEquals(PointerAction.CANCEL, AndroidInputMapping.action(MotionEvent.ACTION_POINTER_UP, MotionEvent.FLAG_CANCELED))
        assertEquals(PointerAction.POINTER_UP, AndroidInputMapping.action(MotionEvent.ACTION_POINTER_UP))
        assertEquals(PointerAction.OTHER, AndroidInputMapping.action(MotionEvent.ACTION_SCROLL))
    }

    @Test
    fun mapsToolsAndButtons() {
        assertEquals(PointerTool.ERASER, AndroidInputMapping.tool(MotionEvent.TOOL_TYPE_ERASER))
        assertEquals(PointerTool.PALM, AndroidInputMapping.tool(5))
        assertEquals(PointerTool.UNKNOWN, AndroidInputMapping.tool(MotionEvent.TOOL_TYPE_UNKNOWN))
        assertEquals(
            PointerButtons.STYLUS_PRIMARY + PointerButtons.PRIMARY,
            AndroidInputMapping.buttons(MotionEvent.BUTTON_STYLUS_PRIMARY or MotionEvent.BUTTON_PRIMARY),
        )
        assertEquals(PointerButtons.STYLUS_SECONDARY, AndroidInputMapping.buttons(MotionEvent.BUTTON_STYLUS_SECONDARY))
        assertEquals(PointerButtons.NONE, AndroidInputMapping.buttons(MotionEvent.BUTTON_TERTIARY))
    }
}
