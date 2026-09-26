package dev.tab2mac.receiver.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import dev.tab2mac.protocol.Fingerprint
import dev.tab2mac.receiver.AppLog
import java.math.BigInteger
import java.net.Socket
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Principal
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.util.Date
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLEngine
import javax.net.ssl.X509ExtendedKeyManager
import javax.security.auth.x500.X500Principal

/**
 * This tablet's TLS identity for Wi‑Fi (PROTOCOL.md §6): a P-256 key in the AndroidKeyStore,
 * which never leaves the secure hardware, and the self-signed certificate the KeyStore issued
 * for it. It is the TLS client certificate the Mac requires; the Mac pins its [fingerprint] when
 * pairing. Clearing the app's data deletes it, and the tablet then pairs again.
 */
class TabletIdentity private constructor(private val privateKey: PrivateKey, private val chain: Array<X509Certificate>) {
    /** SHA-256 of the certificate's DER, as the Mac computes it. */
    val fingerprint: Fingerprint = Fingerprint.of(chain.first().encoded)

    /** Presents this identity as the TLS client certificate. */
    val keyManager: X509ExtendedKeyManager = object : X509ExtendedKeyManager() {
        override fun chooseClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, socket: Socket?): String? =
            ALIAS.takeIf { keyType.acceptsEc() }

        override fun chooseEngineClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, engine: SSLEngine?): String? =
            ALIAS.takeIf { keyType.acceptsEc() }

        override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?): Array<String> = arrayOf(ALIAS)

        override fun getCertificateChain(alias: String?): Array<X509Certificate>? = chain.clone().takeIf { alias == ALIAS }

        override fun getPrivateKey(alias: String?): PrivateKey? = privateKey.takeIf { alias == ALIAS }

        override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?): Array<String>? = null

        override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?): String? = null
    }

    companion object {
        private const val ALIAS = "tab2mac-wifi-identity"
        private const val PROVIDER = "AndroidKeyStore"

        /** Loads the identity, creating it on first use: a key generation, so never on the main thread. */
        fun loadOrCreate(): TabletIdentity {
            val store = KeyStore.getInstance(PROVIDER).apply { load(null) }
            (store.getEntry(ALIAS, null) as? KeyStore.PrivateKeyEntry)?.let { return it.toIdentity() }
            val now = System.currentTimeMillis()
            val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                // SHA-256 signs the certificate. NONE lets TLS sign the handshake digest it computed
                // itself, which is how Conscrypt uses keys it can't read.
                .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_NONE)
                .setCertificateSubject(X500Principal("CN=Tab2Mac tablet"))
                .setCertificateSerialNumber(BigInteger(63, SecureRandom()).add(BigInteger.ONE))
                .setCertificateNotBefore(Date(now - TimeUnit.DAYS.toMillis(1)))
                .setCertificateNotAfter(Date(now + TimeUnit.DAYS.toMillis(20 * 365)))
                .build()
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, PROVIDER).apply { initialize(spec) }.generateKeyPair()
            val identity = (store.getEntry(ALIAS, null) as KeyStore.PrivateKeyEntry).toIdentity()
            AppLog.i("identity.created", "fingerprint" to identity.fingerprint.hex)
            return identity
        }

        private fun KeyStore.PrivateKeyEntry.toIdentity() =
            TabletIdentity(privateKey, certificateChain.map { it as X509Certificate }.toTypedArray())

        private fun Array<out String>?.acceptsEc(): Boolean = this == null || any { it.startsWith("EC", ignoreCase = true) }
    }
}
