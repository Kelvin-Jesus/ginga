package dev.tab2mac.receiver.ui.widget

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import dev.tab2mac.receiver.R
import dev.tab2mac.receiver.ui.Motion
import dev.tab2mac.receiver.ui.themeColor
import dev.tab2mac.receiver.ui.themeDimension
import dev.tab2mac.receiver.ui.themeResource

/**
 * Segmented (design/ginga-design/components/Segmented.md): 2–4 short options visible at once.
 * A surface-2 track, a thumb that slides under the chosen option with ease-ginga in dur-ui
 * (translation only), options of equal width.
 */
class SegmentedControl @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : FrameLayout(context, attrs) {
    private val density = resources.displayMetrics.density
    private val thumb = View(context)
    private val row = LinearLayout(context)
    private var selected = -1
    private var laidOut = false

    /** Called with the index the user picked (not when set from code). */
    var onChange: ((Int) -> Unit)? = null

    init {
        setBackgroundResource(R.drawable.g_seg_track)
        val inset = (3 * density).toInt()
        setPadding(inset, inset, inset, inset)
        thumb.background = context.getDrawable(context.themeResource(R.attr.gingaSegmentThumb))
        thumb.elevation = context.themeDimension(R.attr.gingaCardElevation)
        thumb.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        addView(thumb, LayoutParams(0, LayoutParams.MATCH_PARENT))
        row.orientation = LinearLayout.HORIZONTAL
        row.isMeasureWithLargestChildEnabled = true
        // Same Z as the thumb's shadow elevation, so the labels draw above it (child order decides).
        row.elevation = thumb.elevation
        row.outlineProvider = null
        addView(row, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
    }

    fun setOptions(labels: List<CharSequence>, selectedIndex: Int) {
        row.removeAllViews()
        labels.forEachIndexed { index, label ->
            val option = TextView(context).apply {
                text = label
                gravity = Gravity.CENTER
                setTextAppearance(R.style.TextAppearance_Ginga_Label)
                minHeight = (38 * density).toInt()
                val padding = resources.getDimensionPixelSize(R.dimen.ginga_space_4)
                setPadding(padding, 0, padding, 0)
                isClickable = true
                isFocusable = true
                foreground = context.getDrawable(R.drawable.g_focus_ring_card)
                setOnClickListener {
                    if (index != selected) {
                        select(index, animate = true)
                        onChange?.invoke(index)
                    }
                }
            }
            row.addView(option, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }
        selected = -1
        select(selectedIndex, animate = false)
    }

    fun select(index: Int, animate: Boolean) {
        if (index == selected) return
        selected = index
        for (i in 0 until row.childCount) {
            val option = row.getChildAt(i) as TextView
            option.isSelected = i == index
            option.setTextColor(context.themeColor(if (i == index) R.attr.gingaInk else R.attr.gingaInkMuted))
        }
        placeThumb(animate && laidOut && !Motion.reduced(context))
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        val first = row.getChildAt(0) ?: return
        // The thumb is as wide as one option (they all are, like CSS grid 1fr).
        thumb.layout(paddingLeft, paddingTop, paddingLeft + first.width, paddingTop + row.height)
        laidOut = true
        placeThumb(animate = false)
    }

    private fun placeThumb(animate: Boolean) {
        val option = row.getChildAt(selected) ?: return
        val x = option.left.toFloat()
        thumb.animate().cancel()
        if (animate) {
            thumb.animate().translationX(x).setDuration(Motion.DUR_UI).setInterpolator(Motion.easeGinga).start()
        } else {
            thumb.translationX = x
        }
    }
}
