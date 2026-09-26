package dev.tab2mac.renderer

import android.content.Context
import android.graphics.Color
import android.util.AttributeSet
import android.view.Surface
import android.view.SurfaceView
import android.view.ViewGroup

/**
 * A full-screen container that shows the stream in a [SurfaceView] (hardware overlay, not a
 * TextureView — research §4), letterboxed to the video's aspect ratio for portrait and landscape
 * streams alike.
 *
 * The SurfaceView's buffer is fixed to the video size, so the decoder writes 1:1 and the display
 * compositor scales. [videoRect] is where the picture lands inside this view — the rectangle that
 * input coordinates must be normalised against.
 */
class VideoSurfaceLayout @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : ViewGroup(context, attrs, defStyleAttr) {

    /** The output surface's view. Use its holder for the Surface lifecycle. */
    val surfaceView: SurfaceView = SurfaceView(context)

    private var videoWidth = 0
    private var videoHeight = 0

    /** Where the video is drawn, in this view's coordinates. */
    var videoRect: VideoRect = VideoRect.EMPTY
        private set

    /** Called on the main thread whenever [videoRect] changes. */
    var onVideoRectChanged: ((VideoRect) -> Unit)? = null

    init {
        setBackgroundColor(Color.BLACK)
        addView(surfaceView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    /** Sets the decoded picture size (e.g. from STREAM_FORMAT). Main thread. */
    fun setVideoSize(width: Int, height: Int) {
        if (width == videoWidth && height == videoHeight) return
        videoWidth = width
        videoHeight = height
        if (width > 0 && height > 0) surfaceView.holder.setFixedSize(width, height)
        RendererLog.i("surface.video-size", "width" to width, "height" to height)
        requestLayout()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = getDefaultSize(suggestedMinimumWidth, widthMeasureSpec)
        val height = getDefaultSize(suggestedMinimumHeight, heightMeasureSpec)
        setMeasuredDimension(width, height)
        val rect = AspectFit.fit(videoWidth, videoHeight, width, height)
        surfaceView.measure(
            MeasureSpec.makeMeasureSpec(rect.width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(rect.height, MeasureSpec.EXACTLY),
        )
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val rect = AspectFit.fit(videoWidth, videoHeight, right - left, bottom - top)
        surfaceView.layout(rect.left, rect.top, rect.right, rect.bottom)
        if (rect != videoRect) {
            videoRect = rect
            RendererLog.i("surface.video-rect", "rect" to rect)
            onVideoRectChanged?.invoke(rect)
        }
    }
}

/** Frame-rate voting for the output surface (research §4). */
object SurfaceFrameRate {
    /**
     * Asks the display to run at [fps] for this surface
     * (`FRAME_RATE_COMPATIBILITY_FIXED_SOURCE`, `CHANGE_FRAME_RATE_ALWAYS`). Returns false if the
     * surface rejected the request.
     */
    fun apply(surface: Surface, fps: Float): Boolean {
        if (!surface.isValid || fps <= 0f) return false
        return try {
            surface.setFrameRate(fps, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE, Surface.CHANGE_FRAME_RATE_ALWAYS)
            RendererLog.i("surface.frame-rate", "fps" to fps)
            true
        } catch (e: RuntimeException) {
            RendererLog.w("surface.frame-rate-rejected", "fps" to fps, "error" to e.toString())
            false
        }
    }
}
