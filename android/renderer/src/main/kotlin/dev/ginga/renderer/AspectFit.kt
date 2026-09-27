package dev.ginga.renderer

/** A rectangle in view pixels: where the video is drawn inside its container. */
data class VideoRect(val left: Int, val top: Int, val width: Int, val height: Int) {
    val right: Int get() = left + width
    val bottom: Int get() = top + height
    val isEmpty: Boolean get() = width <= 0 || height <= 0

    companion object {
        val EMPTY = VideoRect(0, 0, 0, 0)
    }
}

/** Letterboxing: the largest rectangle with the video's aspect ratio, centred in the container. */
object AspectFit {
    /**
     * Fits a [contentWidth]×[contentHeight] picture into a [containerWidth]×[containerHeight]
     * container. An unknown content size fills the container.
     */
    fun fit(contentWidth: Int, contentHeight: Int, containerWidth: Int, containerHeight: Int): VideoRect {
        if (containerWidth <= 0 || containerHeight <= 0) return VideoRect.EMPTY
        if (contentWidth <= 0 || contentHeight <= 0) return VideoRect(0, 0, containerWidth, containerHeight)
        val contentIsWider = contentWidth.toLong() * containerHeight >= contentHeight.toLong() * containerWidth
        return if (contentIsWider) {
            val height = roundedDiv(containerWidth.toLong() * contentHeight, contentWidth.toLong()).coerceAtMost(containerHeight)
            VideoRect(0, (containerHeight - height) / 2, containerWidth, height)
        } else {
            val width = roundedDiv(containerHeight.toLong() * contentWidth, contentHeight.toLong()).coerceAtMost(containerWidth)
            VideoRect((containerWidth - width) / 2, 0, width, containerHeight)
        }
    }

    private fun roundedDiv(numerator: Long, denominator: Long): Int = ((2 * numerator + denominator) / (2 * denominator)).toInt()
}
