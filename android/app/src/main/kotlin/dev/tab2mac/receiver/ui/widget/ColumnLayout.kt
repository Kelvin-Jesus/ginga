package dev.tab2mac.receiver.ui.widget

import android.content.Context
import android.util.AttributeSet
import android.widget.LinearLayout
import dev.tab2mac.receiver.R

/** A vertical column no wider than `maxColumnWidth`, so lines stay readable on a 13" tablet. */
class ColumnLayout @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : LinearLayout(context, attrs) {
    private val maxColumnWidth: Int

    init {
        orientation = VERTICAL
        val a = context.obtainStyledAttributes(attrs, R.styleable.ColumnLayout)
        maxColumnWidth = a.getDimensionPixelSize(R.styleable.ColumnLayout_maxColumnWidth, Int.MAX_VALUE)
        a.recycle()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val spec = if (width > maxColumnWidth) MeasureSpec.makeMeasureSpec(maxColumnWidth, MeasureSpec.EXACTLY) else widthMeasureSpec
        super.onMeasure(spec, heightMeasureSpec)
    }
}
