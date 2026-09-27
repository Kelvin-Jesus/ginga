package dev.ginga.receiver.adb

import android.content.Context
import dev.ginga.protocol.Hello
import dev.ginga.protocol.TransportKind

/**
 * The adb loopback token (architecture §5): 32 random bytes the Mac makes on every start and hands
 * to this app through adb ([LoopbackTokenReceiver]). Over adb-tcp HELLO carries it, so the Mac
 * can tell this app from any other local process reaching 127.0.0.1:47800. It is a secret:
 * never logged.
 */
object LoopbackToken {
    private const val LENGTH = 64

    /** [text] if it is exactly 64 lowercase hex digits, else null. */
    fun parse(text: String?): String? =
        text?.takeIf { it.length == LENGTH && it.all { c -> c in '0'..'9' || c in 'a'..'f' } }

    /** [hello] with [token] over adb-tcp; without any token over every other transport. */
    fun applyTo(hello: Hello, token: String?): Hello =
        hello.copy(loopbackToken = if (hello.transport == TransportKind.ADB_TCP) token else null)
}

/** Where the token survives an app restart. */
interface TokenPersistence {
    fun read(): String?

    fun write(token: String)
}

/**
 * The current loopback token: in memory, backed by [persistence]. Only a well-formed token is
 * kept; anything else leaves the current one in place. Thread-safe.
 */
class LoopbackTokenStore(private val persistence: TokenPersistence) {
    @Volatile
    private var cached: String? = null

    @Volatile
    private var loaded = false

    /** The token to send, or null before the Mac has handed one over. */
    val token: String?
        get() {
            if (!loaded) synchronized(this) {
                if (!loaded) {
                    cached = LoopbackToken.parse(persistence.read())
                    loaded = true
                }
            }
            return cached
        }

    /** Keeps [text] if it is a well-formed token; returns whether it was. */
    fun offer(text: String?): Boolean {
        val token = LoopbackToken.parse(text) ?: return false
        synchronized(this) {
            cached = token
            loaded = true
            persistence.write(token)
        }
        return true
    }
}

/** App-private SharedPreferences (excluded from backups: the app has `allowBackup="false"`). */
class PreferencesTokenPersistence(context: Context) : TokenPersistence {
    private val preferences = context.applicationContext.getSharedPreferences("adb", Context.MODE_PRIVATE)

    override fun read(): String? = preferences.getString(KEY, null)

    override fun write(token: String) {
        preferences.edit().putString(KEY, token).apply()
    }

    private companion object {
        const val KEY = "loopbackToken"
    }
}
