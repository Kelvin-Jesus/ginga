package dev.ginga.protocol

import java.util.Base64
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json

/**
 * The JSON configuration for control messages (§1.2):
 * - unknown keys are ignored and missing optional fields default to null;
 * - null optionals are omitted, like Swift's `encodeIfPresent`;
 * - required fields are always written, even when equal to a Kotlin default.
 */
@OptIn(ExperimentalSerializationApi::class)
val ProtocolJson: Json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
}

/** Binary data as standard, padded base64 (what Swift's `JSONEncoder` produces for `Data`). */
object Base64ByteArraySerializer : KSerializer<ByteArray> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("dev.ginga.protocol.Base64ByteArray", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: ByteArray) {
        encoder.encodeString(Base64.getEncoder().encodeToString(value))
    }

    override fun deserialize(decoder: Decoder): ByteArray {
        val text = decoder.decodeString()
        return try {
            Base64.getDecoder().decode(text)
        } catch (e: IllegalArgumentException) {
            throw kotlinx.serialization.SerializationException("invalid base64: ${e.message}")
        }
    }
}
