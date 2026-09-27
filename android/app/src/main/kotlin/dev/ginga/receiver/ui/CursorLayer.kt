package dev.ginga.receiver.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LongSparseArray
import android.view.Choreographer
import android.view.View
import android.widget.ImageView
import dev.ginga.protocol.CursorPosition
import dev.ginga.protocol.CursorShape
import dev.ginga.receiver.AppLog
import dev.ginga.receiver.session.CursorSink
import dev.ginga.renderer.CursorGeometry
import dev.ginga.renderer.VideoRect
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The pointer drawn by the tablet (§3.3b): an [ImageView] above the video, moved with
 * `translationX/Y` and scaled with `scaleX/Y` — no relayout, no GL, no per-message allocation.
 *
 * - Session thread ([CursorSink]): shapes are decoded once, off the main thread, and cached by id
 *   for the session (a [LongSparseArray], no boxing); positions only overwrite the latest one.
 * - Main thread: at most one update per vsync (Choreographer), applying whatever is latest.
 *
 * Process-wide like the controller; the stream screen [attach]es its view while it is shown.
 */
class CursorLayer : CursorSink {
    private class Image(val bitmap: Bitmap, val width: Int, val height: Int, val hotspotX: Int, val hotspotY: Int)

    private val lock = Any()
    private val shapes = LongSparseArray<Image>()
    private var x = 0
    private var y = 0
    private var visible = false
    private var shapeId = 0L

    // Main thread only.
    private var view: ImageView? = null
    private var choreographer: Choreographer? = null
    private var shown: Image? = null
    private var videoRect = VideoRect.EMPTY
    private var streamWidth = 0

    private val scheduled = AtomicBoolean(false)
    private val frame = Choreographer.FrameCallback { apply() }

    override fun onCursorShape(shape: CursorShape) {
        val bitmap = BitmapFactory.decodeByteArray(shape.png, 0, shape.png.size)
        if (bitmap == null) {
            AppLog.w("cursor.shape-undecodable", "shape" to shape.shapeId, "bytes" to shape.png.size)
            return
        }
        val image = Image(bitmap, shape.width.takeIf { it > 0 } ?: bitmap.width, shape.height.takeIf { it > 0 } ?: bitmap.height, shape.hotspotX, shape.hotspotY)
        synchronized(lock) { shapes.put(shape.shapeId, image) }
        schedule()
    }

    override fun onCursor(position: CursorPosition) {
        synchronized(lock) {
            x = position.x
            y = position.y
            visible = position.visible
            shapeId = position.shapeId
        }
        schedule()
    }

    override fun onCursorReset() {
        synchronized(lock) {
            shapes.clear()
            visible = false
        }
        schedule()
    }

    /** The stream screen shows [imageView] (main thread). */
    fun attach(imageView: ImageView) {
        view = imageView.apply {
            pivotX = 0f
            pivotY = 0f
            visibility = View.GONE
        }
        shown = null
        choreographer = Choreographer.getInstance()
        scheduled.set(false)
        schedule()
    }

    /** The stream screen goes away (main thread). */
    fun detach() {
        choreographer?.removeFrameCallback(frame)
        choreographer = null
        view = null
        shown = null
        scheduled.set(false)
    }

    /** Where the video is drawn in the view, and its width in stream pixels (main thread). */
    fun setVideoGeometry(rect: VideoRect, streamWidth: Int) {
        videoRect = rect
        this.streamWidth = streamWidth
        schedule()
    }

    /** Latest wins: one pending frame callback at most. Any thread. */
    private fun schedule() {
        val choreographer = choreographer ?: return
        if (scheduled.compareAndSet(false, true)) choreographer.postFrameCallback(frame)
    }

    private fun apply() {
        scheduled.set(false)
        val view = view ?: return
        val image: Image?
        val px: Int
        val py: Int
        synchronized(lock) {
            image = if (visible) shapes.get(shapeId) else null
            px = x
            py = y
        }
        val rect = videoRect
        if (image == null || rect.isEmpty || streamWidth <= 0) {
            if (view.visibility != View.GONE) view.visibility = View.GONE
            return
        }
        if (image !== shown) {
            shown = image
            view.setImageBitmap(image.bitmap)
            view.layoutParams = view.layoutParams.apply {
                width = image.width
                height = image.height
            }
        }
        val scale = CursorGeometry.scale(rect.width, streamWidth)
        if (view.scaleX != scale) {
            view.scaleX = scale
            view.scaleY = scale
        }
        val left = CursorGeometry.left(px, image.hotspotX, rect, scale)
        val top = CursorGeometry.top(py, image.hotspotY, rect, scale)
        if (view.translationX != left || view.translationY != top) {
            view.translationX = left
            view.translationY = top
            // The video's SurfaceView sits below the window, which tells the compositor which of
            // its areas are transparent. That hint is only recomputed on a layout pass, and a
            // translation isn't one: without this the pointer, once moved, lands in an area still
            // marked transparent and the compositor skips it (it showed only where it last had a
            // layout). One cheap pass per frame, and only while the pointer moves.
            view.requestLayout()
        }
        if (view.visibility != View.VISIBLE) view.visibility = View.VISIBLE
    }
}
