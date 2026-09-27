package dev.ginga.receiver.ui.widget

import android.animation.AnimatorInflater
import android.content.Context
import android.os.Build
import android.util.AttributeSet
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Checkable
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import dev.ginga.receiver.R
import dev.ginga.receiver.ui.Motion

/**
 * A settings row with a Switch (components/Switch.md): label and optional subtitle on the left,
 * the toggle on the right; the whole 56dp row is the touch target and reads as one switch to
 * TalkBack. On: cobalt track, the thumb slides with ease-ginga (it passes a little and comes
 * back) and a spark of seven stars leaves it; off: no spark. Pressing widens the thumb.
 */
class SwitchRow @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) : LinearLayout(context, attrs), Checkable {
    private val density = resources.displayMetrics.density
    private val label = TextView(context)
    private val sub = TextView(context)
    private val control = FrameLayout(context)
    private val track = View(context)
    private val thumb = View(context)
    private var checked = false

    /** Called when the user toggles it (not when set from code). */
    var onCheckedChange: ((Boolean) -> Unit)? = null

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(56)
        val h = resources.getDimensionPixelSize(R.dimen.ginga_space_4)
        val v = resources.getDimensionPixelSize(R.dimen.ginga_space_3)
        setPadding(h, v, h, v)
        isClickable = true
        isFocusable = true
        foreground = context.getDrawable(R.drawable.g_focus_ring_card)
        stateListAnimator = AnimatorInflater.loadStateListAnimator(context, R.animator.g_press)

        val texts = LinearLayout(context).apply { orientation = VERTICAL }
        label.setTextAppearance(R.style.TextAppearance_Ginga_Body)
        sub.setTextAppearance(R.style.TextAppearance_Ginga_Caption)
        texts.addView(label)
        texts.addView(sub)
        addView(texts, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))

        track.setBackgroundResource(R.drawable.g_switch_track)
        thumb.setBackgroundResource(R.drawable.g_switch_thumb)
        thumb.elevation = 1.5f * density
        control.addView(track, FrameLayout.LayoutParams(dp(44), dp(26)))
        control.addView(thumb, FrameLayout.LayoutParams(dp(20), dp(20)).apply { setMargins(dp(3), dp(3), 0, 0) })
        control.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        addView(control, LayoutParams(dp(44), dp(26)).apply { marginStart = resources.getDimensionPixelSize(R.dimen.ginga_space_3) })

        val a = context.obtainStyledAttributes(attrs, R.styleable.SwitchRow)
        label.text = a.getString(R.styleable.SwitchRow_label)
        setSub(a.getString(R.styleable.SwitchRow_sub))
        a.recycle()
        place(animate = false)
    }

    fun setSub(text: CharSequence?) {
        sub.text = text
        sub.visibility = if (text.isNullOrEmpty()) GONE else VISIBLE
    }

    override fun isChecked(): Boolean = checked

    override fun setChecked(value: Boolean) = set(value, fromUser = false)

    override fun toggle() = set(!checked, fromUser = true)

    override fun performClick(): Boolean {
        toggle()
        val handled = super.performClick()
        sendAccessibilityEvent(AccessibilityEvent.TYPE_VIEW_CLICKED)
        return handled
    }

    private fun set(value: Boolean, fromUser: Boolean) {
        if (value == checked) return
        checked = value
        place(animate = fromUser && isAttachedToWindow && !Motion.reduced(context))
        if (fromUser) {
            if (value) Spark.burst(control)
            onCheckedChange?.invoke(value)
        }
    }

    private fun place(animate: Boolean) {
        track.isActivated = checked
        val x = if (checked) 18f * density else 0f
        thumb.animate().cancel()
        if (animate) {
            thumb.animate().translationX(x).setDuration(Motion.DUR_UI).setInterpolator(Motion.easeGinga).start()
        } else {
            thumb.translationX = x
        }
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        // Pressing widens the thumb (20 → 24dp), towards the middle of the track.
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                thumb.pivotX = if (checked) thumb.width.toFloat() else 0f
                thumb.animate().scaleX(1.2f).setDuration(Motion.DUR_TAP).setInterpolator(Motion.easeOut).start()
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> thumb.scaleX = 1f
        }
        return super.dispatchTouchEvent(event)
    }

    override fun getAccessibilityClassName(): CharSequence = Switch::class.java.name

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.isCheckable = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            info.setChecked(if (checked) AccessibilityNodeInfo.CHECKED_STATE_TRUE else AccessibilityNodeInfo.CHECKED_STATE_FALSE)
        } else {
            @Suppress("DEPRECATION")
            info.isChecked = checked
        }
        info.text = listOfNotNull(label.text, sub.text.takeIf { sub.visibility == VISIBLE }).joinToString(". ")
    }

    private fun dp(value: Int): Int = (value * density).toInt()
}
