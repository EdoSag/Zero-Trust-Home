package dev.sagron.zerotrusthome

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import chip.devicecontroller.ChipDeviceController
import chip.devicecontroller.ChipDeviceControllerException
import chip.devicecontroller.ControllerParams
import chip.devicecontroller.GetConnectedDeviceCallbackJni.GetConnectedDeviceCallback
import chip.devicecontroller.ICDDeviceInfo
import chip.devicecontroller.InvokeCallback
import chip.devicecontroller.ReportCallback
import chip.devicecontroller.UnpairDeviceCallback
import chip.devicecontroller.model.ChipAttributePath
import chip.devicecontroller.model.ChipEventPath
import chip.devicecontroller.model.ChipPathId
import chip.devicecontroller.model.InvokeElement
import chip.devicecontroller.model.NodeState
import chip.platform.AndroidBleManager
import chip.platform.AndroidChipPlatform
import chip.platform.AndroidNfcCommissioningManager
import chip.platform.ChipMdnsCallbackImpl
import chip.platform.DiagnosticDataProviderImpl
import chip.platform.NsdManagerServiceBrowser
import chip.platform.NsdManagerServiceResolver
import chip.platform.PreferencesConfigurationManager
import chip.platform.PreferencesKeyValueStoreManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Matter library (project-chip/connectedhomeip) for the Dart side
 * (`lib/adapters/matter/matter_bridge.dart`), over the channel
 * `dev.sagron.zerotrusthome/matter`.
 *
 * The library controls one fabric at a time, as one process-wide
 * controller; `start` replaces it. Node and fabric ids travel as 16 hex
 * digits. Everything here runs on the main thread: the library's own
 * callbacks arrive on its thread and are posted over.
 *
 * Errors: `unsupported` (the library can't run on this phone: it is built
 * for 64-bit ARM), `unreachable` (no answer from the device), `failed`.
 */
class MatterPlugin(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private val context = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
        current = this
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (current === this) current = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "phoneKey" -> result.success(MatterPhoneKey.publicKey(call.argument("fabricId")!!))
                "start" -> start(call, result)
                "pair" -> pair(call, result)
                "cancelPair" -> {
                    failPairing("failed", "Cancelled")
                    result.success(null)
                }
                "read" -> read(call, result)
                "subscribe" -> subscribe(call, result)
                "unsubscribe" -> {
                    unsubscribe(call.argument<Number>("subscription")!!.toInt())
                    result.success(null)
                }
                "invoke" -> invoke(call, result)
                "remove" -> remove(call, result)
                else -> result.notImplemented()
            }
        } catch (e: LinkageError) {
            // No native library for this phone's processor.
            result.error("unsupported", e.message, null)
        } catch (e: Exception) {
            Log.w(TAG, "${call.method} failed", e)
            result.error(codeOf(e), describe(e), null)
        }
    }

    // --- The fabric -------------------------------------------------------

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val fabricId: String = call.argument("fabricId")!!
        val rootCert: ByteArray = call.argument("rootCert")!!
        val certificate: ByteArray = call.argument("certificate")!!
        val ipk: ByteArray = call.argument("ipk")!!
        val adminSubject = id(call.argument("adminSubject")!!)

        ensurePlatform(context)
        stopController()
        val made = ChipDeviceController(
            ControllerParams.newBuilder()
                .setControllerVendorId(VENDOR_ID)
                .setFabricId(id(fabricId))
                .setRootCertificate(rootCert)
                .setOperationalCertificate(certificate)
                .setKeypairDelegate(MatterPhoneKey.Delegate(fabricId))
                .setIpk(ipk)
                .setAdminSubject(adminSubject)
                .build(),
        )
        made.setCompletionListener(Completion(made))
        // Each device being added sends a signing request; its certificate
        // is issued in Dart, where the home's key is.
        made.setNOCChainIssuer { csr, _ ->
            val request = csr.getCSR()
            main.post { issue(made, request, rootCert, ipk, adminSubject) }
        }
        controller = made
        result.success(null)
    }

    private fun issue(
        on: ChipDeviceController,
        csr: ByteArray,
        rootCert: ByteArray,
        ipk: ByteArray,
        adminSubject: Long,
    ) {
        if (controller !== on) return
        val plugin = current ?: return failPairing("failed", "The app closed")
        plugin.channel.invokeMethod(
            "issueDevice",
            mapOf("csr" to csr),
            object : MethodChannel.Result {
                override fun success(value: Any?) {
                    if (controller !== on) return
                    val cert = value as? ByteArray
                        ?: return failPairing("failed", "No certificate")
                    try {
                        val code = on.onNOCChainGeneration(
                            ControllerParams.newBuilder()
                                .setRootCertificate(rootCert)
                                // None, but the library wants the field.
                                .setIntermediateCertificate(ByteArray(0))
                                .setOperationalCertificate(cert)
                                .setIpk(ipk)
                                .setAdminSubject(adminSubject)
                                .build(),
                        )
                        if (code != 0L) failPairing("failed", "Certificate refused (${hex(code)})")
                    } catch (e: Exception) {
                        failPairing("failed", describe(e))
                    }
                }

                override fun error(code: String, message: String?, details: Any?) =
                    failPairing("failed", message ?: code)

                override fun notImplemented() = failPairing("failed", "issueDevice")
            },
        )
    }

    // --- Adding a device --------------------------------------------------

    private fun pair(call: MethodCall, result: MethodChannel.Result) {
        val on = controller ?: return result.error("failed", "No fabric started", null)
        if (pairing != null) return result.error("failed", "Already adding a device", null)
        val nodeId = id(call.argument("nodeId")!!)
        val timeout = Runnable { failPairing("unreachable", "No device answered") }
        pairing = Pairing(nodeId, result, timeout)
        main.postDelayed(timeout, PAIR_TIMEOUT_MS)
        try {
            // Found on the network only: the device is on Wi-Fi already.
            @Suppress("DEPRECATION")
            on.pairDeviceWithCode(nodeId, call.argument<String>("code")!!, false, true, null, null)
        } catch (e: Exception) {
            failPairing(codeOf(e), describe(e))
        }
    }

    private fun finishPairing() {
        val done = pairing ?: return
        pairing = null
        main.removeCallbacks(done.timeout)
        done.result.success(null)
    }

    private fun failPairing(code: String, message: String) {
        val failed = pairing ?: return
        pairing = null
        main.removeCallbacks(failed.timeout)
        try {
            controller?.stopDevicePairing(failed.nodeId)
        } catch (e: Exception) {
            Log.w(TAG, "stopDevicePairing", e)
        }
        failed.result.error(code, message, null)
    }

    private inner class Completion(private val on: ChipDeviceController) :
        ChipDeviceController.CompletionListener {
        private fun mine(action: () -> Unit) {
            main.post { if (controller === on) action() }
        }

        override fun onCommissioningComplete(nodeId: Long, errorCode: Long) = mine {
            if (errorCode == 0L) finishPairing() else failPairing(codeOf(errorCode), hex(errorCode))
        }

        override fun onPairingComplete(errorCode: Long) = mine {
            if (errorCode != 0L) failPairing(codeOf(errorCode), hex(errorCode))
        }

        override fun onError(error: Throwable) = mine {
            failPairing("failed", error.message ?: error.toString())
        }

        override fun onCommissioningStatusUpdate(nodeId: Long, stage: String, errorCode: Long) {
            Log.i(TAG, "Commissioning $stage ${hex(errorCode)}")
        }

        override fun onConnectDeviceComplete() {}
        override fun onStatusUpdate(status: Int) {}
        override fun onPairingDeleted(errorCode: Long) {}
        override fun onReadCommissioningInfo(
            vendorId: Int,
            productId: Int,
            wifiEndpointId: Int,
            threadEndpointId: Int,
        ) {}
        override fun onCommissioningStageStart(nodeId: Long, stage: String) {}
        override fun onNotifyChipConnectionClosed() {}
        override fun onCloseBleComplete() {}
        override fun onOpCSRGenerationComplete(csr: ByteArray) {}
        override fun onICDRegistrationInfoRequired() {}
        override fun onICDRegistrationComplete(errorCode: Long, icdDeviceInfo: ICDDeviceInfo) {}
    }

    // --- Talking to a device ----------------------------------------------

    /** Runs [action] with a session to the node; [failed] when there is none. */
    private fun connected(
        nodeId: Long,
        failed: (String, String) -> Unit,
        action: (ChipDeviceController, Long) -> Unit,
    ) {
        val on = controller ?: return failed("failed", "No fabric started")
        on.getConnectedDevicePointer(
            nodeId,
            object : GetConnectedDeviceCallback {
                override fun onDeviceConnected(devicePointer: Long) {
                    main.post {
                        if (controller !== on) return@post failed("failed", "Another home is in use")
                        try {
                            action(on, devicePointer)
                        } catch (e: Exception) {
                            failed(codeOf(e), describe(e))
                        }
                    }
                }

                override fun onConnectionFailure(nodeId: Long, error: Exception) {
                    main.post { failed("unreachable", describe(error)) }
                }
            },
        )
    }

    private fun paths(call: MethodCall): List<ChipAttributePath> =
        call.argument<List<List<Number>>>("paths")!!.map { (endpoint, cluster, attribute) ->
            ChipAttributePath.newInstance(
                if (endpoint.toInt() < 0) ChipPathId.forWildcard() else ChipPathId.forId(endpoint.toLong()),
                ChipPathId.forId(cluster.toLong()),
                ChipPathId.forId(attribute.toLong()),
            )
        }

    /** Rows of endpoint, cluster, attribute and the value's TLV bytes. */
    private fun rows(state: NodeState): List<List<Any>> {
        val rows = ArrayList<List<Any>>()
        for ((endpoint, clusters) in state.endpointStates) {
            for ((cluster, attributes) in clusters.clusterStates) {
                for ((attribute, value) in attributes.attributeStates) {
                    val tlv = value.tlv ?: continue
                    rows.add(listOf(endpoint, cluster, attribute, tlv))
                }
            }
        }
        return rows
    }

    private fun read(call: MethodCall, result: MethodChannel.Result) {
        val nodeId = id(call.argument("nodeId")!!)
        val wanted = paths(call)
        var answered = false
        fun answer(action: () -> Unit) {
            if (answered) return
            answered = true
            action()
        }
        connected(nodeId, { code, message -> answer { result.error(code, message, null) } }) { on, device ->
            val found = ArrayList<List<Any>>()
            var problem: Exception? = null
            on.readPath(
                object : ReportCallback {
                    override fun onError(
                        attributePath: ChipAttributePath?,
                        eventPath: ChipEventPath?,
                        e: Exception,
                    ) {
                        main.post { problem = e }
                    }

                    override fun onReport(nodeState: NodeState) {
                        val part = rows(nodeState)
                        main.post { found.addAll(part) }
                    }

                    override fun onDone() {
                        main.post {
                            release(on, device)
                            val failed = problem
                            answer {
                                if (found.isEmpty() && failed != null) {
                                    result.error(codeOf(failed), describe(failed), null)
                                } else {
                                    result.success(found)
                                }
                            }
                        }
                    }
                },
                device,
                wanted,
                null,
                false,
                0,
                null,
            )
        }
    }

    private fun invoke(call: MethodCall, result: MethodChannel.Result) {
        val nodeId = id(call.argument("nodeId")!!)
        val element = InvokeElement.newInstance(
            call.argument<Number>("endpoint")!!.toInt(),
            call.argument<Number>("cluster")!!.toLong(),
            call.argument<Number>("command")!!.toLong(),
            call.argument<ByteArray>("fields")!!,
            null,
        )
        var answered = false
        fun answer(action: () -> Unit) {
            if (answered) return
            answered = true
            action()
        }
        connected(nodeId, { code, message -> answer { result.error(code, message, null) } }) { on, device ->
            on.invoke(
                object : InvokeCallback {
                    override fun onError(e: Exception) {
                        main.post { answer { result.error(codeOf(e), describe(e), null) } }
                    }

                    override fun onResponse(invokeElement: InvokeElement?, successCode: Long) {
                        main.post { answer { result.success(null) } }
                    }

                    override fun onDone() {
                        main.post {
                            release(on, device)
                            answer { result.success(null) }
                        }
                    }
                },
                device,
                element,
                0,
                0,
            )
        }
    }

    private fun remove(call: MethodCall, result: MethodChannel.Result) {
        val on = controller ?: return result.error("failed", "No fabric started", null)
        val nodeId = id(call.argument("nodeId")!!)
        on.unpairDeviceCallback(
            nodeId,
            object : UnpairDeviceCallback {
                override fun onError(status: Int, remoteDeviceId: Long) {
                    main.post { result.error("unreachable", "Status $status", null) }
                }

                override fun onSuccess(remoteDeviceId: Long) {
                    main.post { result.success(null) }
                }
            },
        )
    }

    // --- Following a device -----------------------------------------------

    private fun subscribe(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<Number>("subscription")!!.toInt()
        val nodeId = id(call.argument("nodeId")!!)
        val wanted = paths(call)
        val following = Following(key, nodeId)
        subscriptions[key] = following
        // The answer only says the request was taken; what follows comes
        // as `report`, `reachable` and `subscriptionFailed`.
        result.success(null)
        connected(nodeId, { _, message -> ended(following, message) }) { on, device ->
            if (subscriptions[key] !== following) return@connected release(on, device)
            following.on = on
            following.device = device
            on.subscribeToPath(
                { subscriptionId ->
                    main.post {
                        following.subscriptionId = subscriptionId
                        // Unsubscribed while it was being set up.
                        if (subscriptions[key] !== following) close(following)
                    }
                },
                { _, _ -> main.post { tell(following, "reachable", mapOf("reachable" to false)) } },
                object : ReportCallback {
                    override fun onError(
                        attributePath: ChipAttributePath?,
                        eventPath: ChipEventPath?,
                        e: Exception,
                    ) {
                        Log.i(TAG, "Subscription to ${hex(nodeId)}: ${describe(e)}")
                    }

                    override fun onReport(nodeState: NodeState) {
                        val part = rows(nodeState)
                        main.post { tell(following, "report", mapOf("attributes" to part)) }
                    }

                    override fun onDone() {
                        main.post { ended(following, "Subscription ended") }
                    }
                },
                device,
                wanted,
                null,
                MIN_INTERVAL_S,
                MAX_INTERVAL_S,
                false,
                false,
                0,
                null,
            )
        }
    }

    private fun tell(following: Following, method: String, values: Map<String, Any>) {
        if (subscriptions[following.key] !== following) return
        current?.channel?.invokeMethod(method, values + ("subscription" to following.key))
    }

    /** The library gave up on the subscription, or never got one. */
    private fun ended(following: Following, message: String) {
        if (subscriptions[following.key] !== following) return
        subscriptions.remove(following.key)
        release(following.on, following.device)
        following.device = 0
        current?.channel?.invokeMethod(
            "subscriptionFailed",
            mapOf("subscription" to following.key, "message" to message),
        )
    }

    private fun unsubscribe(key: Int) {
        val following = subscriptions.remove(key) ?: return
        close(following)
    }

    private fun close(following: Following) {
        val on = following.on ?: return
        val subscriptionId = following.subscriptionId ?: return
        if (controller === on) {
            try {
                on.shutdownSubscriptions(on.fabricIndex, following.nodeId, subscriptionId)
            } catch (e: Exception) {
                Log.w(TAG, "shutdownSubscriptions", e)
            }
        }
        release(on, following.device)
        following.device = 0
    }

    private fun release(on: ChipDeviceController?, device: Long) {
        if (on == null || device == 0L || controller !== on) return
        try {
            on.releaseConnectedDevicePointer(device)
        } catch (e: Exception) {
            Log.w(TAG, "releaseConnectedDevicePointer", e)
        }
    }

    private class Pairing(
        val nodeId: Long,
        val result: MethodChannel.Result,
        val timeout: Runnable,
    )

    private class Following(val key: Int, val nodeId: Long) {
        var on: ChipDeviceController? = null
        var device: Long = 0
        var subscriptionId: Long? = null
    }

    companion object {
        private const val TAG = "ZtMatter"
        private const val CHANNEL = "dev.sagron.zerotrusthome/matter"

        // A test vendor id: ZT Home has none of its own. Devices show it
        // as the name of this controller's maker.
        private const val VENDOR_ID = 0xFFF4
        private const val PAIR_TIMEOUT_MS = 90_000L
        private const val MIN_INTERVAL_S = 0
        private const val MAX_INTERVAL_S = 60

        // CHIP_ERROR_TIMEOUT: nothing answered.
        private const val ERROR_TIMEOUT = 0x32L

        // Process-wide, as the library is: they outlive an activity that is
        // made again.
        private var platform: AndroidChipPlatform? = null
        private var controller: ChipDeviceController? = null
        private var pairing: Pairing? = null
        private val subscriptions = HashMap<Int, Following>()
        private var current: MatterPlugin? = null

        private fun ensurePlatform(context: Context) {
            if (platform != null) return
            ChipDeviceController.loadJni()
            platform = AndroidChipPlatform(
                AndroidBleManager(context),
                AndroidNfcCommissioningManager(),
                PreferencesKeyValueStoreManager(context),
                PreferencesConfigurationManager(context),
                NsdManagerServiceResolver(
                    context,
                    NsdManagerServiceResolver.NsdManagerResolverAvailState(),
                ),
                NsdManagerServiceBrowser(context),
                ChipMdnsCallbackImpl(),
                DiagnosticDataProviderImpl(context),
            )
        }

        /** Ends the controller of the fabric that was served until now. */
        private fun stopController() {
            val old = controller ?: return
            pairing?.let {
                pairing = null
                Handler(Looper.getMainLooper()).removeCallbacks(it.timeout)
                it.result.error("failed", "Another home is in use", null)
            }
            subscriptions.clear()
            controller = null
            try {
                old.shutdownSubscriptions()
            } catch (e: Exception) {
                Log.w(TAG, "shutdownSubscriptions", e)
            }
            try {
                old.close()
            } catch (e: Exception) {
                Log.w(TAG, "close", e)
            }
        }

        /** 16 hex digits as the 64-bit id they are (the top bit may be set). */
        private fun id(hex: String): Long = java.lang.Long.parseUnsignedLong(hex, 16)

        private fun hex(value: Long): String = "0x" + java.lang.Long.toHexString(value)

        private fun codeOf(errorCode: Long): String =
            if (errorCode == ERROR_TIMEOUT) "unreachable" else "failed"

        private fun codeOf(e: Throwable): String =
            if (e is ChipDeviceControllerException) codeOf(e.errorCode) else "failed"

        private fun describe(e: Throwable): String =
            if (e is ChipDeviceControllerException) {
                "${e.message ?: "Matter error"} (${hex(e.errorCode)})"
            } else {
                e.message ?: e.toString()
            }
    }
}
