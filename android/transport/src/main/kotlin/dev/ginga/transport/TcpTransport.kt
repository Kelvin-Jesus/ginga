package dev.ginga.transport

import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

/** Settings of a [TcpTransport]. The defaults are the §5 ADB binding. */
data class TcpTransportConfig(
    /** Loopback only: `adb reverse` tunnels it to the Mac; the stream never touches the LAN. */
    val host: String = "127.0.0.1",
    val port: Int = DEFAULT_PORT,
    /** Reconnect after a failure or disconnect, following [reconnectPolicy]. */
    val autoReconnect: Boolean = true,
    val reconnectPolicy: ReconnectPolicy = ReconnectPolicy(),
    val connectTimeoutMs: Int = 2_000,
    /** Received messages buffered before the reader blocks; see [LinkOptions.incomingCapacity]. */
    val incomingCapacity: Int = 8,
    /** `SO_RCVBUF`; null keeps the system default (no hidden queueing). */
    val receiveBufferBytes: Int? = null,
    val readChunkBytes: Int = 256 * 1024,
    /** How long [TcpTransport.close] / [TcpTransport.suspend] let queued messages (e.g. GOODBYE) drain. */
    val closeDrainTimeoutMs: Long = 300,
    /** Nothing received for this long while streaming, or a write blocked this long: reconnect ([LinkOptions.silenceTimeoutMs]). */
    val silenceTimeoutMs: Long? = 5_000,
) {
    internal fun linkOptions() = LinkOptions(
        autoReconnect, reconnectPolicy, incomingCapacity, readChunkBytes, closeDrainTimeoutMs, silenceTimeoutMs = silenceTimeoutMs,
    )

    companion object {
        /** `adb reverse tcp:47800 tcp:47800` (§5). */
        const val DEFAULT_PORT: Int = 47800
    }
}

/**
 * [Transport] over TCP with `TCP_NODELAY`, used through `adb reverse` (M4): the tablet connects
 * to 127.0.0.1:47800 and adbd forwards to the Mac. With `adb reverse` in place but no Mac
 * listening, adbd accepts and closes at once; such links never become healthy, so they are
 * retried with growing delays. See [LinkTransport] for the threads and policies.
 */
class TcpTransport(
    config: TcpTransportConfig = TcpTransportConfig(),
    nanoClock: () -> Long = System::nanoTime,
) : LinkTransport(
    endpoint = "tcp://${config.host}:${config.port}",
    opener = SocketOpener(config),
    options = config.linkOptions(),
    nanoClock = nanoClock,
    threadPrefix = "ginga-tcp",
)

private class SocketOpener(private val config: TcpTransportConfig) : LinkOpener {
    override fun open(): LinkAttempt {
        val socket = Socket()
        return try {
            socket.tcpNoDelay = true
            config.receiveBufferBytes?.let { socket.receiveBufferSize = it }
            socket.connect(InetSocketAddress(config.host, config.port), config.connectTimeoutMs)
            LinkAttempt.Opened(SocketLink(socket))
        } catch (e: IOException) {
            try {
                socket.close()
            } catch (_: IOException) {
            }
            LinkAttempt.Failed(e.message ?: e.javaClass.simpleName)
        }
    }
}

private class SocketLink(private val socket: Socket) : ByteLink {
    override val input: InputStream = socket.getInputStream()
    override val output: OutputStream = socket.getOutputStream()

    override fun shutdownOutput() {
        if (!socket.isClosed) socket.shutdownOutput()
    }

    override fun close() {
        socket.close()
    }
}
