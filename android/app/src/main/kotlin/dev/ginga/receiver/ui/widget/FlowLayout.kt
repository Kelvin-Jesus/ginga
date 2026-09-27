package dev.ginga.receiver.ui.widget

import android.content.Context
import android.util.AttributeSet
import android.view.View
import android.view.ViewGroup
import dev.ginga.receiver.R
import kotlin.math.max

/**
 * Children side by side with `flowGap` between them, like a horizontal LinearLayout, but a child
 * that doesn't fit starts a new line (`flowGap` below the previous one) instead of being clipped:
 * button pairs and the method chips on a phone or with a large font. Where everything fits (the
 * tablet) it is a single row. Lines start at the start edge, or are centred with `flowCenter`;
 * children are centred vertically in their line. Children's margins are ignored: use the gap.
 */
class FlowLayout @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : ViewGroup(context, attrs) {
    private val gap: Int
    private val centered: Boolean

    /** Index of the first child of each line after the first, from the last measure. */
    private val breaks = ArrayList<Int>()

    init {
        val a = context.obtainStyledAttributes(attrs, R.styleable.FlowLayout)
        gap = a.getDimensionPixelSize(R.styleable.FlowLayout_flowGap, 0)
        centered = a.getBoolean(R.styleable.FlowLayout_flowCenter, false)
        a.recycle()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val available = if (MeasureSpec.getMode(widthMeasureSpec) == MeasureSpec.UNSPECIFIED) {
            Int.MAX_VALUE
        } else {
            MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight
        }
        breaks.clear()
        var lineWidth = 0
        var lineHeight = 0
        var inLine = 0
        var widest = 0
        var height = 0
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == View.GONE) continue
            measureChild(child, widthMeasureSpec, heightMeasureSpec)
            val w = child.measuredWidth
            if (inLine > 0 && lineWidth + gap + w > available) {
                breaks.add(i)
                widest = max(widest, lineWidth)
                height += lineHeight + gap
                lineWidth = w
                lineHeight = child.measuredHeight
                inLine = 1
            } else {
                lineWidth += if (inLine > 0) gap + w else w
                lineHeight = max(lineHeight, child.measuredHeight)
                inLine++
            }
        }
        widest = max(widest, lineWidth)
        height += lineHeight
        setMeasuredDimension(
            resolveSize(widest + paddingLeft + paddingRight, widthMeasureSpec),
            resolveSize(height + paddingTop + paddingBottom, heightMeasureSpec),
        )
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val content = r - l - paddingLeft - paddingRight
        val rtl = layoutDirection == LAYOUT_DIRECTION_RTL
        var top = paddingTop
        var start = 0
        while (start < childCount) {
            val end = breaks.firstOrNull { it > start } ?: childCount
            val line = (start until end).map(::getChildAt).filter { it.visibility != View.GONE }
            val lineWidth = line.sumOf { it.measuredWidth } + gap * max(0, line.size - 1)
            val lineHeight = line.maxOfOrNull { it.measuredHeight } ?: 0
            var x = if (centered) (content - lineWidth) / 2 else 0
            for (child in line) {
                val left = if (rtl) paddingLeft + content - x - child.measuredWidth else paddingLeft + x
                val y = top + (lineHeight - child.measuredHeight) / 2
                child.layout(left, y, left + child.measuredWidth, y + child.measuredHeight)
                x += child.measuredWidth + gap
            }
            top += lineHeight + gap
            start = end
        }
    }
}
