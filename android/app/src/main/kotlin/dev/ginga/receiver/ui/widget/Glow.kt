package dev.ginga.receiver.ui.widget

import android.view.View
import android.view.ViewOutlineProvider

/**
 * A small coloured halo (glow-star, the status planet in Black espacial): the view's own
 * elevation shadow tinted with [color]. Drawn by the render thread with the view, no extra layer.
 */
object Glow {
    fun apply(view: View, color: Int, elevationDp: Float = 4f) {
        view.outlineProvider = ViewOutlineProvider.BACKGROUND
        view.elevation = elevationDp * view.resources.displayMetrics.density
        view.outlineAmbientShadowColor = color
        view.outlineSpotShadowColor = color
    }
}
