package dev.sagron.zerotrusthome

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The quick controls' copy of the account's devices (see
 * `lib/quick/quick_snapshot.dart`): one file, sealed with AES-GCM under a
 * key that lives in the Android Keystore and never leaves it. Only this app
 * on this phone can open it. It sits in the no-backup folder, so it is
 * never backed up, and is deleted on sign-out or when quick controls are
 * turned off.
 */
object QuickVault {
    private const val STORE = "AndroidKeyStore"
    private const val ALIAS = "zt-home.quick"
    private const val FILE = "quick.sealed"
    private const val TAG = "ZtQuick"

    private fun file(context: Context) = File(context.noBackupFilesDir, FILE)

    @Synchronized
    private fun key(): SecretKey {
        val store = KeyStore.getInstance(STORE).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, STORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    @Synchronized
    fun save(context: Context, text: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        val iv = cipher.iv
        val out = File(context.noBackupFilesDir, "$FILE.new")
        out.writeBytes(byteArrayOf(iv.size.toByte()) + iv + sealed)
        // All or nothing: the panel never reads half a file.
        if (!out.renameTo(file(context))) {
            out.delete()
            throw IllegalStateException("Couldn't save the quick controls")
        }
    }

    /** The copy, or null when there is none or it can't be opened. */
    @Synchronized
    fun load(context: Context): String? {
        val f = file(context)
        if (!f.exists()) return null
        return try {
            val bytes = f.readBytes()
            val ivLength = bytes[0].toInt()
            val iv = bytes.copyOfRange(1, 1 + ivLength)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(bytes, 1 + ivLength, bytes.size - 1 - ivLength), Charsets.UTF_8)
        } catch (e: Exception) {
            Log.w(TAG, "Couldn't open the quick controls", e)
            null
        }
    }

    @Synchronized
    fun clear(context: Context) {
        file(context).delete()
    }

    /** The channel `dev.sagron.zerotrusthome/quick`, for the Dart side. */
    fun serve(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, "dev.sagron.zerotrusthome/quick").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "save" -> {
                        save(app, call.argument<String>("text")!!)
                        QuickEngine.refresh()
                        result.success(null)
                    }
                    "load" -> result.success(load(app))
                    "clear" -> {
                        clear(app)
                        QuickEngine.refresh()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("failed", e.message, null)
            }
        }
    }
}
