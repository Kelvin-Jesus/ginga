package dev.ginga.receiver.ui.widget

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import dev.ginga.receiver.R
import dev.ginga.receiver.ui.Motion
import dev.ginga.receiver.ui.themeColor
import dev.ginga.receiver.ui.themeDimension
import dev.ginga.receiver.ui.themeResource
import kotlin.math.ceil

/**
 * Segmented (design/ginga-design/components/Segmented.md): 2–4 short options visible at once.
 * A surface-2 track, a thumb that slides under the chosen option with ease-ginga in dur-ui
 * (translation only), options of equal width.
 *
 * As wide as its widest option times their number when that fits (the tablet). When it doesn't
 * (a phone), or when the parent gives it an exact width, the options share the width it has, with
 * tighter padding, and a long label wraps onto two lines instead of being cut off.
 */
class SegmentedControl @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : FrameLayout(context, attrs) {
    private val density = resources.displayMetrics.density
    private val thumb = View(context)
    private val row = LinearLayout(context)
    private var selected = -1
    private var laidOut = false

    /** The options share the width given (instead of each being as wide as the widest). */
    private var filling = false

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
        applyFill(filling)
        selected = -1
        select(selectedIndex, animate = false)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val count = row.childCount
        if (count > 0) {
            // The natural width, from the labels on one line with the usual padding (not from
            // measuring, so the choice below is stable and never loops).
            val padding = 2 * resources.getDimensionPixelSize(R.dimen.ginga_space_4)
            val widest = (0 until count).maxOf { i ->
                val option = row.getChildAt(i) as TextView
                ceil(option.paint.measureText(option.text.toString())).toInt() + padding
            }
            val natural = widest * count + paddingLeft + paddingRight
            val size = MeasureSpec.getSize(widthMeasureSpec)
            val fill = when (MeasureSpec.getMode(widthMeasureSpec)) {
                MeasureSpec.EXACTLY -> size != natural
                MeasureSpec.AT_MOST -> natural > size
                else -> false
            }
            if (fill != filling) applyFill(fill)
        }
        // Sharing: exactly the width it was given, so each option gets an equal part of it.
        val spec = if (filling) MeasureSpec.makeMeasureSpec(MeasureSpec.getSize(widthMeasureSpec), MeasureSpec.EXACTLY) else widthMeasureSpec
        super.onMeasure(spec, heightMeasureSpec)
    }

    private fun applyFill(fill: Boolean) {
        filling = fill
        row.layoutParams.width = if (fill) LayoutParams.MATCH_PARENT else LayoutParams.WRAP_CONTENT
        row.isMeasureWithLargestChildEnabled = !fill
        // A label on two lines: every option as tall as the tallest, labels centred (not on one baseline).
        row.isBaselineAligned = !fill
        val padding = resources.getDimensionPixelSize(if (fill) R.dimen.ginga_space_2 else R.dimen.ginga_space_4)
        for (i in 0 until row.childCount) {
            val option = row.getChildAt(i)
            option.setPadding(padding, 0, padding, 0)
            option.layoutParams.height = if (fill) LinearLayout.LayoutParams.MATCH_PARENT else LinearLayout.LayoutParams.WRAP_CONTENT
        }
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
