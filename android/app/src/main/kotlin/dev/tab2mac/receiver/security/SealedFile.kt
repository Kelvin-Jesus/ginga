package dev.tab2mac.receiver.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import dev.tab2mac.receiver.AppLog
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.ProviderException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * A small text file in app-private storage excluded from backups, sealed with AES-256-GCM under a
 * key that stays in the AndroidKeyStore ([keyAlias]). A file that is missing, tampered with or
 * unreadable reads as null. Contents are never logged.
 */
class SealedFile(context: Context, fileName: String, private val keyAlias: String) {
    private val file = AtomicFile(File(context.applicationContext.noBackupFilesDir, fileName))

    fun read(): String? {
        val bytes = try {
            file.readFully()
        } catch (_: FileNotFoundException) {
            return null
        } catch (e: IOException) {
            AppLog.e("sealed.read-failed", e, "file" to file.baseFile.name)
            return null
        }
        return try {
            require(bytes.size > 2 && bytes[0] == FORMAT) { "unknown sealed file format" }
            val ivLength = bytes[1].toInt() and 0xFF
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, bytes, 2, ivLength))
            cipher.doFinal(bytes, 2 + ivLength, bytes.size - 2 - ivLength).decodeToString()
        } catch (e: GeneralSecurityException) {
            unreadable(e)
        } catch (e: IOException) {
            unreadable(e)
        } catch (e: IllegalArgumentException) {
            unreadable(e)
        } catch (e: ProviderException) {
            unreadable(e)
        }
    }

    /** Replaces the contents atomically; failures are logged and leave the old file. */
    fun write(text: String) {
        val sealed: ByteArray
        val iv: ByteArray
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key()) // the KeyStore picks a fresh IV
            sealed = cipher.doFinal(text.encodeToByteArray())
            iv = cipher.iv
        } catch (e: GeneralSecurityException) {
            return AppLog.e("sealed.seal-failed", e, "file" to file.baseFile.name)
        } catch (e: IOException) {
            return AppLog.e("sealed.seal-failed", e, "file" to file.baseFile.name)
        } catch (e: ProviderException) {
            return AppLog.e("sealed.seal-failed", e, "file" to file.baseFile.name)
        }
        val out = try {
            file.startWrite()
        } catch (e: IOException) {
            return AppLog.e("sealed.write-failed", e, "file" to file.baseFile.name)
        }
        try {
            out.write(byteArrayOf(FORMAT, iv.size.toByte()))
            out.write(iv)
            out.write(sealed)
            file.finishWrite(out)
        } catch (e: IOException) {
            file.failWrite(out)
            AppLog.e("sealed.write-failed", e, "file" to file.baseFile.name)
        }
    }

    private fun unreadable(error: Exception): String? {
        AppLog.e("sealed.unreadable", error, "file" to file.baseFile.name)
        return null
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(PROVIDER).apply { load(null) }
        (store.getKey(keyAlias, null) as? SecretKey)?.let { return it }
        val spec = KeyGenParameterSpec.Builder(keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER).apply { init(spec) }.generateKey()
    }

    private companion object {
        const val FORMAT: Byte = 1
        const val PROVIDER = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val TAG_BITS = 128
    }
}
