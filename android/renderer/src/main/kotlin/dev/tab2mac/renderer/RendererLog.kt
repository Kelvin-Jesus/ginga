package dev.tab2mac.renderer

import android.util.Log

/** Structured logging for this module: tag `T2M/renderer`, messages `event key=value …`. */
internal object RendererLog {
    private const val TAG = "T2M/renderer"

    fun i(event: String, vararg fields: Pair<String, Any?>) {
        Log.i(TAG, format(event, fields))
    }

    fun w(event: String, vararg fields: Pair<String, Any?>) {
        Log.w(TAG, format(event, fields))
    }

    private fun format(event: String, fields: Array<out Pair<String, Any?>>): String = buildString {
        append(event)
        for ((key, value) in fields) {
            append(' ').append(key).append('=')
            val text = value?.toString() ?: "nil"
            if (text.isEmpty() || text.any { it.isWhitespace() || it == '"' }) {
                append('"').append(text.replace("\"", "\\\"")).append('"')
            } else {
                append(text)
            }
        }
    }
}
