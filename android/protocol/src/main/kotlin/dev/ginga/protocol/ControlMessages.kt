package dev.ginga.protocol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// JSON control messages (§3.1). Field names and optionality mirror the Swift implementation
// (mac/Sources/GingaProtocol/Messages.swift): optional fields are nullable with a null default
// and are omitted when null; required fields are always encoded. Unknown keys are ignored.
//
// String-valued enumerations are open value classes, so values added by a newer peer survive a
// round trip instead of failing to decode.

/** `codec` of WELCOME / STREAM_FORMAT. */
@Serializable
@JvmInline
value class Codec(val value: String) {
    override fun toString(): String = value

    companion object {
        val HEVC = Codec("hevc")
        val H264 = Codec("h264")
    }
}

/** Display orientation. */
@Serializable
@JvmInline
value class Orientation(val value: String) {
    override fun toString(): String = value

    companion object {
        val LANDSCAPE = Orientation("landscape")
        val PORTRAIT = Orientation("portrait")
    }
}

/** A capability named in HELLO/WELCOME `features`. */
@Serializable
@JvmInline
value class Feature(val value: String) {
    override fun toString(): String = value

    companion object {
        val CLOCK_SYNC = Feature("clock-sync")
        val RECEIVER_REPORT = Feature("receiver-report")

        /** CONFIGURE `request.paused`: the Mac stops capturing and sending video while paused. */
        val PAUSE = Feature("pause")

        /** The tablet draws the pointer from CURSOR / CURSOR_SHAPE (§3.3b); the Mac leaves it out of the video. */
        val CURSOR = Feature("cursor")

        /** The tablet forwards its hardware keyboard as KEY (§3.3c). */
        val KEYBOARD = Feature("keyboard")

        /** The tablet can host a direct Wi‑Fi link without a router (DIRECT_LINK, §6b). */
        val DIRECT_LINK = Feature("direct-link")

        /** HELLO: the tablet can pair over Wi‑Fi with PAIRING (§6). */
        val PAIRING = Feature("pairing")
    }
}

/** HELLO `transport`. */
@Serializable
@JvmInline
value class TransportKind(val value: String) {
    override fun toString(): String = value

    companion object {
        /** TCP through `adb reverse` (§5, M4). */
        val ADB_TCP = TransportKind("adb-tcp")

        /** USB bulk pipes in Android Open Accessory mode (§5, M6). */
        val AOA = TransportKind("aoa")

        /** TLS 1.3 over TCP on the local network (§5–6, M7). */
        val WIFI_TLS = TransportKind("wifi-tls")
    }
}

/** KEYFRAME_REQUEST `reason`. */
@Serializable
@JvmInline
value class KeyframeReason(val value: String) {
    override fun toString(): String = value

    companion object {
        val DECODER_ERROR = KeyframeReason("decoder-error")
        val LOSS = KeyframeReason("loss")
        val STARTUP = KeyframeReason("startup")
    }
}

/** ERROR `code`. */
@Serializable
@JvmInline
value class ErrorCode(val value: String) {
    override fun toString(): String = value

    companion object {
        val INCOMPATIBLE_VERSION = ErrorCode("incompatible-version")
        val BAD_FRAME = ErrorCode("bad-frame")
        val UNSUPPORTED = ErrorCode("unsupported")
        val INTERNAL = ErrorCode("internal")

        /** An adb-tcp HELLO without the Mac's current loopback token (§3.1): retryable. */
        val UNAUTHORIZED = ErrorCode("unauthorized")
    }
}

/** GOODBYE `reason`. */
@Serializable
@JvmInline
value class GoodbyeReason(val value: String) {
    override fun toString(): String = value

    companion object {
        val USER = GoodbyeReason("user")
        val SHUTDOWN = GoodbyeReason("shutdown")
        val ERROR = GoodbyeReason("error")
        val REPLACED = GoodbyeReason("replaced")
    }
}

/** An inclusive protocol version range. */
@Serializable
data class VersionRange(val min: Int, val max: Int) {
    operator fun contains(version: Int): Boolean = version in min..max
}

/** Width and height in pixels (or points, where the field says so). */
@Serializable
data class PixelDimensions(val width: Int, val height: Int)

/** HELLO (Android → Mac): capabilities of the receiver. */
@Serializable
data class Hello(
    @SerialName("protocol") val versions: VersionRange,
    val app: App,
    val device: Device,
    val display: Display,
    val decoders: List<Decoder>,
    val input: Input? = null,
    val transport: TransportKind? = null,
    val features: List<Feature>? = null,
    val resume: Resume? = null,
    /**
     * adb-tcp only: the token the Mac handed over through adb (64 lowercase hex digits), proving
     * that this connection comes from the Ginga app and not from another local process.
     */
    val loopbackToken: String? = null,
    /**
     * wifi-tls only, `true` or absent: the tablet has no pin for the certificate the Mac just
     * presented (or chose to pair again), so the Mac pairs even if it still pins the tablet (§6).
     */
    val pairingRequested: Boolean? = null,
) : ControlMessage {
    override val type: MessageType get() = MessageType.HELLO

    @Serializable
    data class App(val name: String, val version: String)

    /**
     * [id] is a stable, app-scoped random ID; the Mac derives the virtual display serial from it.
     * [name] is the name the owner gave the device (optional, a label only; PROTOCOL.md §3.1 HELLO).
     */
    @Serializable
    data class Device(
        val manufacturer: String,
        val model: String,
        val android: String,
        val id: String,
        val name: String? = null,
    )

    /**
     * The tablet panel in its current orientation. [densityDpi] is the physical pixel density;
     * [rotation] is the display rotation in degrees (0, 90, 180, 270).
     */
    @Serializable
    data class Display(
        val widthPx: Int,
        val heightPx: Int,
        val densityDpi: Int,
        val refreshRates: List<Double>,
        val rotation: Int,
        val wideColor: Boolean? = null,
    )

    @Serializable
    data class Decoder(
        val mime: String,
        val profiles: List<String>,
        val maxWidth: Int,
        val maxHeight: Int,
        val maxFps: Double,
        val lowLatency: Boolean,
    )

    @Serializable
    data class Input(val touch: Touch? = null, val stylus: Stylus? = null) {
        @Serializable
        data class Touch(val maxPointers: Int)

        @Serializable
        data class Stylus(val pressure: Boolean, val tilt: Boolean, val hover: Boolean, val buttons: Int)
    }

    /** Session token from a previous WELCOME, presented on reconnection. */
    @Serializable
    data class Resume(val session: String)
}

/** The virtual display, as announced by the Mac. [id] is the u32 `CGDirectDisplayID`. */
@Serializable
data class DisplayDescription(
    val id: Long,
    val name: String,
    val looksLike: PixelDimensions,
    val hiDPI: Boolean,
    val refreshRate: Double,
    val orientation: Orientation,
)

/** The encoded stream, as announced by the Mac. */
@Serializable
data class StreamDescription(
    val codec: Codec,
    val width: Int,
    val height: Int,
    val fps: Double,
    val bitrateKbps: Int,
    val primaries: String = "bt709",
    val transfer: String = "bt709",
    val matrix: String = "bt709",
    val range: String = "video",
)

/** WELCOME (Mac → Android): the negotiated session. */
@Serializable
data class Welcome(
    @SerialName("protocol") val version: Int,
    val session: String,
    val mac: Mac,
    val display: DisplayDescription,
    val stream: StreamDescription,
    val features: List<Feature>? = null,
) : ControlMessage {
    override val type: MessageType get() = MessageType.WELCOME

    @Serializable
    data class Mac(val name: String, val os: String, val app: String)
}

/**
 * CONFIGURE (both directions). Android sends a [request]; the Mac announces a new [display] /
 * [stream], always followed by STREAM_FORMAT and a keyframe.
 */
@Serializable
data class Configure(
    val request: Request? = null,
    val display: DisplayDescription? = null,
    val stream: StreamDescription? = null,
) : ControlMessage {
    override val type: MessageType get() = MessageType.CONFIGURE

    /**
     * [refreshRate] is a preference the Mac may ignore (its power setting decides). [paused]
     * `true` means the receiver can't show video (app in the background, screen off): the Mac
     * stops capturing and sending frames until `false`. Only sent when WELCOME lists
     * [Feature.PAUSE].
     */
    @Serializable
    data class Request(
        val orientation: Orientation? = null,
        val refreshRate: Double? = null,
        val resolution: PixelDimensions? = null,
        val paused: Boolean? = null,
    )
}

/**
 * STREAM_FORMAT (Mac → Android): codec and parameter sets (VPS/SPS/PPS for HEVC, SPS/PPS for
 * H.264) as NAL units without start codes; base64 in JSON.
 */
@Serializable
class StreamFormat(
    val codec: Codec,
    val width: Int,
    val height: Int,
    val parameterSets: List<@Serializable(with = Base64ByteArraySerializer::class) ByteArray>,
) : ControlMessage {
    override val type: MessageType get() = MessageType.STREAM_FORMAT

    override fun equals(other: Any?): Boolean =
        other is StreamFormat && codec == other.codec && width == other.width && height == other.height &&
            parameterSets.size == other.parameterSets.size &&
            parameterSets.indices.all { parameterSets[it].contentEquals(other.parameterSets[it]) }

    override fun hashCode(): Int =
        parameterSets.fold((codec.hashCode() * 31 + width) * 31 + height) { acc, set -> acc * 31 + set.contentHashCode() }

    override fun toString(): String =
        "StreamFormat(codec=$codec, ${width}x$height, parameterSets=${parameterSets.map { it.size }})"
}

/**
 * RECEIVER_REPORT (Android → Mac): every 1 s on USB, where the bitrate is fixed and reports only
 * feed diagnostics, every 250 ms on Wi‑Fi (the Mac's bitrate controller). Counters cover the
 * report interval.
 */
@Serializable
data class ReceiverReport(
    val lastFrameId: Long? = null,
    val framesReceived: Int? = null,
    val framesDecoded: Int? = null,
    val framesRendered: Int? = null,
    val framesDropped: Int? = null,
    val bytesReceived: Long? = null,
    val decodeMs: Percentiles? = null,
    val endToEndMs: Percentiles? = null,
    val decoderQueue: Int? = null,
    val clockOffsetUs: Long? = null,
    val rttUs: Long? = null,
) : ControlMessage {
    override val type: MessageType get() = MessageType.RECEIVER_REPORT

    @Serializable
    data class Percentiles(val p50: Double, val p95: Double)
}

/** KEYFRAME_REQUEST (Android → Mac). */
@Serializable
data class KeyframeRequest(
    val reason: KeyframeReason,
    val lastDecodedFrameId: Long? = null,
) : ControlMessage {
    override val type: MessageType get() = MessageType.KEYFRAME_REQUEST
}

/** ERROR (both directions). */
@Serializable
data class ErrorMessage(val code: ErrorCode, val message: String) : ControlMessage {
    override val type: MessageType get() = MessageType.ERROR
}

/** GOODBYE (both directions). */
@Serializable
data class Goodbye(val reason: GoodbyeReason) : ControlMessage {
    override val type: MessageType get() = MessageType.GOODBYE
}

/** PAIRING `state` (§6), in the order of the exchange. Receivers ignore values they don't know. */
@Serializable
@JvmInline
value class PairingState(val value: String) {
    override fun toString(): String = value

    companion object {
        /** 1 · Mac → tablet: the tablet isn't pinned; [Pairing.name] names the Mac. */
        val REQUIRED = PairingState("required")

        /** 2 · tablet → Mac: [Pairing.commitment] to the tablet's nonce, before it sees the Mac's. */
        val COMMIT = PairingState("commit")

        /** 3 · Mac → tablet: the Mac's [Pairing.nonce]. */
        val NONCE = PairingState("nonce")

        /** 4 · tablet → Mac: the tablet's [Pairing.nonce]; both screens now show the code. */
        val REVEAL = PairingState("reveal")

        /** 5 · tablet → Mac: its user confirmed that the codes match. */
        val CONFIRMED = PairingState("confirmed")

        /** 6 · Mac → tablet: both users confirmed and the tablet is pinned; WELCOME follows. */
        val PAIRED = PairingState("paired")

        /** Either side: the attempt is over; GOODBYE follows (`user` for a decline, `error` otherwise). */
        val REJECTED = PairingState("rejected")
    }
}

/**
 * PAIRING (both directions, Wi‑Fi only, §6): numeric comparison with a commitment, after TLS,
 * when HELLO lists [Feature.PAIRING]. Framed with IGNORABLE, as every type added after 1.0.
 * [commitment] and [nonce] are 64 lowercase hex digits (32 bytes); see [PairingCode.parseHex].
 */
@Serializable
data class Pairing(
    val state: PairingState,
    val name: String? = null,
    val commitment: String? = null,
    val nonce: String? = null,
) : ControlMessage {
    override val type: MessageType get() = MessageType.PAIRING
}

/**
 * DIRECT_LINK (Mac → tablet, §6b): the no-router key for this tablet, sent after WELCOME over an
 * authenticated session when HELLO lists [Feature.DIRECT_LINK]. [keyId] is 16 hex digits (8 bytes),
 * [key] 64 (32 bytes). A secret: [toString] leaves it out, and it is never logged.
 */
@Serializable
data class DirectLink(val keyId: String, val key: String) : ControlMessage {
    override val type: MessageType get() = MessageType.DIRECT_LINK

    override fun toString(): String = "DirectLink(keyId=$keyId, key=…)"
}
