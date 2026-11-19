package dev.sagron.zerotrusthome

import android.content.Context
import android.content.Intent
import android.net.Uri
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
 * The names the controls panel shows (see `lib/quick/quick_snapshot.dart`;
 * never addresses or keys): one file, sealed with AES-GCM under a key that
 * lives in the Android Keystore and never leaves it. Only this app on this
 * phone can open it. It sits in the no-backup folder, so it is never backed
 * up, and is deleted on sign-out or when "Show devices outside the app" is
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

    // --- Taps waiting for the app to be unlocked --------------------------

    private const val TAPS = "zt-home.quick-tap"
    private const val TAP_MAX_AGE_MS = 2 * 60_000L

    /**
     * What a tile in the panel or on the widget opens: [QuickTapActivity],
     * which no other app can start, so a tap can only come from a tile this
     * app made.
     */
    fun tapIntent(context: Context, action: String, id: String): Intent =
        Intent(context, QuickTapActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            // Unique per tile, so each keeps its own PendingIntent.
            .setData(Uri.parse("zthome-quick://$action/${Uri.encode(id)}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** Keeps the tap [intent] carries, if any; true when it carried one.
     *  Only for [QuickTapActivity]: anything another app can reach must
     *  never call this. */
    fun keepTap(context: Context, intent: Intent?): Boolean {
        val data = intent?.data ?: return false
        if (data.scheme != "zthome-quick") return false
        val action = data.host ?: return false
        val id = data.pathSegments.firstOrNull() ?: return false
        if (action != "toggle" && action != "scene") return false
        // commit, not apply: the app reads it as soon as it comes forward.
        context.getSharedPreferences(TAPS, Context.MODE_PRIVATE).edit()
            .putString("action", action)
            .putString("id", id)
            .putLong("at", System.currentTimeMillis())
            .commit()
        return true
    }

    /** The waiting tap, once. One left too long is dropped: a light that
     *  switches minutes after the tap would be a surprise. */
    private fun takeTap(context: Context): Map<String, String>? {
        val prefs = context.getSharedPreferences(TAPS, Context.MODE_PRIVATE)
        val action = prefs.getString("action", null)
        val id = prefs.getString("id", null)
        val at = prefs.getLong("at", 0)
        prefs.edit().clear().apply()
        if (action == null || id == null) return null
        if (System.currentTimeMillis() - at > TAP_MAX_AGE_MS) return null
        return mapOf("action" to action, "id" to id)
    }

    /** The channel `dev.sagron.zerotrusthome/quick`, for the Dart side. */
    fun serve(context: Context, messenger: BinaryMessenger): MethodChannel {
        val app = context.applicationContext
        val channel = MethodChannel(messenger, "dev.sagron.zerotrusthome/quick")
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "save" -> {
                        save(app, call.argument<String>("text")!!)
                        result.success(null)
                    }
                    "load" -> result.success(load(app))
                    "clear" -> {
                        clear(app)
                        result.success(null)
                    }
                    "takeTap" -> result.success(takeTap(app))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("failed", e.message, null)
            }
        }
        return channel
    }
}
