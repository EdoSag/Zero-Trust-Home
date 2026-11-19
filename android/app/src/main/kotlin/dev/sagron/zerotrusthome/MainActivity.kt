package dev.sagron.zerotrusthome

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity, not FlutterActivity: the biometric prompt
 * (local_auth) needs a FragmentActivity.
 */
class MainActivity : FlutterFragmentActivity(), MatterHost {
    /**
     * Held while the app looks for devices on the home network: without it
     * Android drops the broadcast packets devices announce themselves with.
     */
    private var multicastLock: WifiManager.MulticastLock? = null

    /** The Matter library, for the Dart side. */
    private var matter: MatterPlugin? = null

    // Answers from the system's own screens (permission, Bluetooth, camera).
    private var bluetoothAllowed: ((Boolean) -> Unit)? = null
    private var bluetoothOn: ((Boolean) -> Unit)? = null
    private var qrScanned: ((String?) -> Unit)? = null

    private val askBluetooth =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
            val done = bluetoothAllowed
            bluetoothAllowed = null
            done?.invoke(granted.isNotEmpty() && granted.values.all { it })
        }

    private val askBluetoothOn =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { answer ->
            val done = bluetoothOn
            bluetoothOn = null
            done?.invoke(answer.resultCode == RESULT_OK)
        }

    private val scanQr = registerForActivityResult(ScanContract()) { answer ->
        val done = qrScanned
        qrScanned = null
        done?.invoke(answer.contents)
    }

    /** Scanning for devices: "Nearby devices" from Android 12, location before. */
    private val bluetoothPermissions =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    override fun allowBluetooth(done: (Boolean) -> Unit) {
        val missing = bluetoothPermissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) return done(true)
        // A question still open is answered "no" rather than left hanging.
        bluetoothAllowed?.invoke(false)
        bluetoothAllowed = done
        askBluetooth.launch(missing.toTypedArray())
    }

    override fun turnOnBluetooth(done: (Boolean) -> Unit) {
        bluetoothOn?.invoke(false)
        bluetoothOn = done
        try {
            askBluetoothOn.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
        } catch (e: Exception) {
            bluetoothOn = null
            done(false)
        }
    }

    override fun scanQrCode(done: (String?) -> Unit) {
        qrScanned?.invoke(null)
        qrScanned = done
        scanQr.launch(
            ScanOptions()
                .setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                .setPrompt("")
                .setBeepEnabled(false)
                .setOrientationLocked(false),
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        matter = MatterPlugin(this, flutterEngine.dartExecutor.binaryMessenger, this)
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
