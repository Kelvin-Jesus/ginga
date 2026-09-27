package dev.ginga.receiver

import android.util.Log
import dev.ginga.receiver.session.SessionLog

/** Structured logging for the app: tags `Ginga/app` and `Ginga/session`, messages `event key=value …`. */
object AppLog {
    private const val TAG = "Ginga/app"
    private const val SESSION_TAG = "Ginga/session"

    /** The session's logger. */
    val session: SessionLog = SessionLog { event, fields -> Log.i(SESSION_TAG, format(event, fields)) }

    fun i(event: String, vararg fields: Pair<String, Any?>) {
        Log.i(TAG, format(event, fields.toList()))
    }

    fun w(event: String, vararg fields: Pair<String, Any?>) {
        Log.w(TAG, format(event, fields.toList()))
    }

    fun e(event: String, error: Throwable?, vararg fields: Pair<String, Any?>) {
        Log.e(TAG, format(event, fields.toList()), error)
    }

    /** `event key=value …`; values with spaces or quotes are quoted. */
    fun format(event: String, fields: List<Pair<String, Any?>>): String = buildString {
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
