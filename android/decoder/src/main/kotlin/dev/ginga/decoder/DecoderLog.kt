package dev.ginga.decoder

import android.util.Log

/** Structured logging for this module: tag `Ginga/decoder`, messages `event key=value …`. */
internal object DecoderLog {
    private const val TAG = "Ginga/decoder"

    fun d(event: String, vararg fields: Pair<String, Any?>) {
        Log.d(TAG, format(event, fields))
    }

    fun i(event: String, vararg fields: Pair<String, Any?>) {
        Log.i(TAG, format(event, fields))
    }

    fun w(event: String, vararg fields: Pair<String, Any?>) {
        Log.w(TAG, format(event, fields))
    }

    fun e(event: String, error: Throwable?, vararg fields: Pair<String, Any?>) {
        Log.e(TAG, format(event, fields), error)
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
