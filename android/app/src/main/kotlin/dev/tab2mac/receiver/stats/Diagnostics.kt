package dev.tab2mac.receiver.stats

import java.util.Locale

/** Everything the diagnostics overlay shows. */
data class DiagnosticsSnapshot(
    val connection: String,
    val width: Int?,
    val height: Int?,
    val codec: String?,
    val decoderName: String?,
    val lowLatencyDecoder: Boolean,
    val rates: StreamRates?,
    val rttUs: Long?,
    val clockOffsetUs: Long?,
    /** The panel's current refresh rate (shows whether the frame-rate vote took effect). */
    val displayRefreshHz: Float? = null,
    /** The rate voted for with `Surface.setFrameRate`. */
    val votedFrameRate: Float? = null,
    val power: PowerSample? = null,
    val error: String? = null,
)

/** Renders the overlay text. Pure, so the layout of the numbers is unit-tested. */
object DiagnosticsFormatter {
    fun format(snapshot: DiagnosticsSnapshot): String = buildString {
        appendLine("Ginga · ${snapshot.connection}")
        snapshot.error?.let { appendLine("⚠ $it") }
        val size = if (snapshot.width != null && snapshot.height != null) "${snapshot.width}×${snapshot.height}" else "—"
        val decoder = snapshot.decoderName?.let { name -> " · $name" + if (snapshot.lowLatencyDecoder) " (low-latency)" else "" } ?: ""
        appendLine("$size ${snapshot.codec ?: "—"}$decoder")
        val rates = snapshot.rates
        if (rates != null) {
            appendLine("${fmt("%.1f", rates.fps)} fps · ${fmt("%,.0f", rates.bitrateKbps)} kbps")
            appendLine("decode ${percentiles(rates.decodeMs)}")
            val e2eLabel = if (rates.endToEndDisplayed || rates.endToEndMs == null) "end-to-end" else "end-to-end (at release)"
            appendLine("$e2eLabel ${percentiles(rates.endToEndMs)}")
            appendLine(
                "dropped ${fmt("%,d", rates.totals.framesDropped)} · received ${fmt("%,d", rates.totals.framesReceived)}" +
                    " · input ${fmt("%,d", rates.totals.inputMessages)}",
            )
        }
        if (snapshot.displayRefreshHz != null) {
            val vote = snapshot.votedFrameRate?.let { " (voted ${fmt("%.0f", it)})" } ?: ""
            appendLine("panel ${fmt("%.0f", snapshot.displayRefreshHz)} Hz$vote")
        }
        snapshot.power?.let { power ->
            val watts = power.watts?.let { " · ${fmt("%.2f", it)} W" } ?: ""
            appendLine("battery ${fmt("%+d", power.currentMa)} mA$watts${if (power.charging) " (charging)" else ""}")
        }
        val rtt = snapshot.rttUs?.let { "${fmt("%.2f", it / 1_000.0)} ms" } ?: "—"
        val offset = snapshot.clockOffsetUs?.let { "${fmt("%,d", it)} µs" } ?: "—"
        append("RTT $rtt · clock offset $offset")
    }

    private fun percentiles(summary: LatencySummary?): String =
        summary?.let { "p50 ${fmt("%.1f", it.p50)} ms · p95 ${fmt("%.1f", it.p95)} ms" } ?: "—"

    private fun fmt(pattern: String, value: Any): String = String.format(Locale.US, pattern, value)
}
