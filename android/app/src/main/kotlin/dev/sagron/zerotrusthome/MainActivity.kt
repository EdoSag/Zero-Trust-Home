package dev.sagron.zerotrusthome

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity, not FlutterActivity: the biometric prompt
 * (local_auth) needs a FragmentActivity.
 */
class MainActivity : FlutterFragmentActivity() {
    /**
     * Held while the app looks for devices on the home network: without it
     * Android drops the broadcast packets devices announce themselves with.
     */
    private var multicastLock: WifiManager.MulticastLock? = null

    /** The Matter library, for the Dart side. */
    private var matter: MatterPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        matter = MatterPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.sagron.zerotrusthome/network",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    try {
                        if (multicastLock == null) {
                            val wifi = applicationContext
                                .getSystemService(Context.WIFI_SERVICE) as WifiManager
                            multicastLock = wifi.createMulticastLock("zt-home-discovery")
                                .apply { setReferenceCounted(false) }
                        }
                        multicastLock?.acquire()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("lock", e.message, null)
                    }
                }
                "releaseMulticastLock" -> {
                    releaseMulticastLock()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun releaseMulticastLock() {
        try {
            multicastLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
            // Already released.
        }
    }

    override fun onDestroy() {
        matter?.dispose()
        matter = null
        releaseMulticastLock()
        super.onDestroy()
    }
}
