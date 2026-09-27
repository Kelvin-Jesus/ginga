package dev.tab2mac.receiver.ui

import android.content.Context
import android.util.TypedValue

/** The current theme's value of a Ginga attribute (res/values/attrs.xml). */
fun Context.themeColor(attr: Int): Int = TypedValue().also { theme.resolveAttribute(attr, it, true) }.data

fun Context.themeResource(attr: Int): Int = TypedValue().also { theme.resolveAttribute(attr, it, true) }.resourceId

fun Context.themeBoolean(attr: Int): Boolean = TypedValue().let { theme.resolveAttribute(attr, it, true) && it.data != 0 }

fun Context.themeDimension(attr: Int): Float {
    val value = TypedValue()
    return if (theme.resolveAttribute(attr, value, true)) value.getDimension(resources.displayMetrics) else 0f
}
