package dev.sagron.zerotrusthome

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * A background Flutter engine running `quickMain`
 * (`lib/quick/quick_engine.dart`): the app's own adapters (Matter, Home
 * Assistant, Tuya) working from the quick controls' copy, for the phone's
 * controls panel while the app isn't open. Started on first use and
 * stopped when nothing has used it for a while. Main thread only.
 */
object QuickEngine {
    private const val TAG = "ZtQuick"
    private const val CHANNEL = "dev.sagron.zerotrusthome/quick_engine"
    private const val IDLE_MS = 3 * 60_000L

    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var matter: MatterPlugin? = null
    private var ready = false
    private val waiting = mutableListOf<() -> Unit>()
    private val stopIdle = Runnable { stop() }

    /** Watchers of device states, by the id the service gave them. */
    private val watchers = HashMap<Int, (String, Map<*, *>) -> Unit>()

    /** Calls [method] in Dart once the engine is ready; [done] gets the answer or null. */
    fun call(context: Context, method: String, args: Map<String, Any?>, done: (Any?) -> Unit) {
        touch()
        val send = {
            channel?.invokeMethod(
                method,
                args,
                object : MethodChannel.Result {
                    override fun success(value: Any?) = done(value)
                    override fun error(code: String, message: String?, details: Any?) {
                        Log.w(TAG, "$method: $code $message")
                        done(null)
                    }
                    override fun notImplemented() = done(null)
                },
            ) ?: done(null)
        }
        if (ready) send() else {
            waiting.add(send)
            start(context)
        }
    }

    /** [onState] hears each new state of the devices in [ids] until [unwatch]. */
    fun watch(context: Context, key: Int, ids: List<String>, onState: (String, Map<*, *>) -> Unit) {
        watchers[key] = onState
        call(context, "watch", mapOf("ids" to ids)) {}
    }

    fun unwatch(context: Context, key: Int) {
        watchers.remove(key)
        if (watchers.isEmpty() && engine != null) call(context, "unwatch", emptyMap()) {}
    }

    /** The app saved a new copy: a running engine reads it again. */
    fun refresh() {
        if (ready) channel?.invokeMethod("refresh", null)
    }

    private fun touch() {
        main.removeCallbacks(stopIdle)
        main.postDelayed(stopIdle, IDLE_MS)
    }

    private fun start(context: Context) {
        if (engine != null) return
        val app = context.applicationContext
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(app)
            loader.ensureInitializationComplete(app, null)
            // Registers the app's plugins (secure storage and the rest).
            val made = FlutterEngine(app)
            val messenger = made.dartExecutor.binaryMessenger
            matter = MatterPlugin(app, messenger, NoScreen)
            QuickVault.serve(app, messenger)
            // Tuya's discovery asks for a multicast lock; sending to a
            // known address doesn't need one.
            MethodChannel(messenger, "dev.sagron.zerotrusthome/network")
                .setMethodCallHandler { _, result -> result.success(null) }
            val quick = MethodChannel(messenger, CHANNEL)
            quick.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        ready = true
                        val queued = waiting.toList()
                        waiting.clear()
                        queued.forEach { it() }
                    }
                    "state" -> {
                        val values = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val id = values["id"] as? String
                        if (id != null) watchers.values.toList().forEach { it(id, values) }
                    }
                }
                result.success(null)
            }
            channel = quick
            engine = made
            made.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    "package:zerotrust_home/quick/quick_engine.dart",
                    "quickMain",
                ),
            )
        } catch (e: Exception) {
            Log.w(TAG, "Couldn't start the background engine", e)
            stop()
        }
    }

    private fun stop() {
        main.removeCallbacks(stopIdle)
        if (watchers.isNotEmpty()) return touch()
        val queued = waiting.toList()
        waiting.clear()
        ready = false
        channel = null
        matter?.dispose()
        matter = null
        engine?.destroy()
        engine = null
        // Anything still waiting gets "no answer".
        queued.forEach { it() }
    }

    /** No screen to ask the person anything: adding devices isn't done here. */
    private object NoScreen : MatterHost {
        override fun allowBluetooth(done: (Boolean) -> Unit) = done(false)
        override fun turnOnBluetooth(done: (Boolean) -> Unit) = done(false)
        override fun scanQrCode(done: (String?) -> Unit) = done(null)
    }
}
