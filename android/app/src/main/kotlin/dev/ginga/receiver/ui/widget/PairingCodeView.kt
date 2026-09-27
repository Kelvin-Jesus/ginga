package dev.ginga.receiver.ui.widget

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import dev.ginga.receiver.R
import dev.ginga.receiver.ui.Motion
import dev.ginga.receiver.ui.themeBoolean

/**
 * PairingCode (components/PairingCode.md): the six digits, always in two groups of three
 * ("482 913"), in code-digits. They appear one by one like stars: 60 ms apart, scale 0.6 → 1 and
 * fade in with ease-ginga; with reduced motion, all at once. Screen readers hear "Código 4 8 2 9 1 3".
 */
class PairingCodeView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : LinearLayout(context, attrs) {
    private val digits = List(6) { TextView(context) }
    private var code: String? = null

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER
        clipChildren = false
        val density = resources.displayMetrics.density
        val glow = context.themeBoolean(R.attr.gingaIsSpace)
        for (group in 0..1) {
            val box = LinearLayout(context).apply { orientation = HORIZONTAL; clipChildren = false }
            for (i in 0..2) {
                val digit = digits[group * 3 + i]
                digit.setTextAppearance(R.style.TextAppearance_Ginga_CodeDigits)
                digit.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
                // Black espacial: the code has a light cobalt glow (text-shadow 0 0 18px, 45%).
                if (glow) digit.setShadowLayer(18f * density / 2f, 0f, 0f, 0x736F82FF)
                box.addView(digit, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                    if (i > 0) marginStart = (2 * density).toInt()
                })
            }
            addView(box, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                if (group > 0) marginStart = resources.getDimensionPixelSize(R.dimen.ginga_space_4)
            })
        }
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
    }

    /** Shows [value] (six digits); a new code makes the digits appear again, one by one. */
    fun setCode(value: String) {
        if (value == code) return
        code = value
        val clean = value.filter { it.isDigit() }.padEnd(6).take(6)
        contentDescription = context.getString(R.string.pairing_code_a11y, clean.trim().toList().joinToString(" "))
        val reduced = Motion.reduced(context)
        digits.forEachIndexed { index, view ->
            view.text = clean[index].toString()
            view.animate().cancel()
            if (reduced) {
                view.alpha = 1f
                view.scaleX = 1f
                view.scaleY = 1f
            } else {
                view.alpha = 0f
                view.scaleX = 0.6f
                view.scaleY = 0.6f
                view.animate()
                    .alpha(1f).scaleX(1f).scaleY(1f)
                    .setStartDelay(Motion.staggerDelay(index, Motion.DIGIT_STAGGER))
                    .setDuration(Motion.DUR_SHEET)
                    .setInterpolator(Motion.easeGinga)
                    .start()
            }
        }
    }
}
