package dev.sagron.zerotrusthome

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import chip.devicecontroller.KeypairDelegate
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec

/**
 * This phone's own key in one home's Matter fabric. It lives in the Android
 * Keystore and can't be taken out of it: the Matter library asks for each
 * signature through [Delegate].
 */
object MatterPhoneKey {
    private const val STORE = "AndroidKeyStore"

    private fun alias(fabricId: String) = "matter.phone.$fabricId"

    private fun store(): KeyStore = KeyStore.getInstance(STORE).apply { load(null) }

    /** The public key as 65 bytes (04, X, Y); the key is made on first use. */
    @Synchronized
    fun publicKey(fabricId: String): ByteArray {
        val name = alias(fabricId)
        val store = store()
        if (!store.containsAlias(name)) {
            val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, STORE)
            generator.initialize(
                KeyGenParameterSpec.Builder(name, KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .build(),
            )
            generator.generateKeyPair()
        }
        val point = (store().getCertificate(name).publicKey as ECPublicKey).w
        return byteArrayOf(4) + fixed(point.affineX.toByteArray()) +
            fixed(point.affineY.toByteArray())
    }

    /** A coordinate as exactly 32 bytes (BigInteger adds or drops a zero). */
    private fun fixed(value: ByteArray): ByteArray {
        val out = ByteArray(32)
        val from = maxOf(0, value.size - 32)
        val count = value.size - from
        System.arraycopy(value, from, out, 32 - count, count)
        return out
    }

    class Delegate(private val fabricId: String) : KeypairDelegate {
        override fun generatePrivateKey() {
            try {
                publicKey(fabricId)
            } catch (e: Exception) {
                throw KeypairDelegate.KeypairException("No phone key", e)
            }
        }

        // The phone's certificate is issued in Dart from the public key.
        override fun createCertificateSigningRequest(): ByteArray =
            throw KeypairDelegate.KeypairException("Not used")

        override fun getPublicKey(): ByteArray =
            try {
                publicKey(fabricId)
            } catch (e: Exception) {
                throw KeypairDelegate.KeypairException("No phone key", e)
            }

        /** ECDSA over SHA-256 of [message], as a DER signature. */
        override fun ecdsaSignMessage(message: ByteArray): ByteArray =
            try {
                val key = store().getKey(alias(fabricId), null) as PrivateKey
                Signature.getInstance("SHA256withECDSA").run {
                    initSign(key)
                    update(message)
                    sign()
                }
            } catch (e: Exception) {
                throw KeypairDelegate.KeypairException("Signing failed", e)
            }
    }
}
