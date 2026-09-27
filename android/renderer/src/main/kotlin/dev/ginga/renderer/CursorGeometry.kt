package dev.ginga.renderer

/**
 * Where to draw the pointer image (§3.3b). Positions are normalized to 0…65535 across the display,
 * images are in stream pixels: `x·videoWidth/65535 − hotspotX·s`, with `s` the view's pixels per
 * stream pixel, offset by the letterboxed video rect. Pure, so it's unit-tested.
 */
object CursorGeometry {
    private const val MAX_POSITION = 65535f

    /** View pixels per stream pixel. */
    fun scale(videoWidth: Int, streamWidth: Int): Float = if (streamWidth > 0) videoWidth.toFloat() / streamWidth else 1f

    /** The image's left edge, in the video view's coordinates. */
    fun left(x: Int, hotspotX: Int, rect: VideoRect, scale: Float): Float = rect.left + x * rect.width / MAX_POSITION - hotspotX * scale

    /** The image's top edge, in the video view's coordinates. */
    fun top(y: Int, hotspotY: Int, rect: VideoRect, scale: Float): Float = rect.top + y * rect.height / MAX_POSITION - hotspotY * scale
}
