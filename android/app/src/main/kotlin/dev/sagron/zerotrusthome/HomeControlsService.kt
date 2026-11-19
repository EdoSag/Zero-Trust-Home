package dev.sagron.zerotrusthome

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.controls.Control
import android.service.controls.ControlsProviderService
import android.service.controls.DeviceTypes
import android.service.controls.actions.BooleanAction
import android.service.controls.actions.CommandAction
import android.service.controls.actions.ControlAction
import android.service.controls.actions.FloatAction
import android.service.controls.templates.ControlButton
import android.service.controls.templates.ControlTemplate
import android.service.controls.templates.RangeTemplate
import android.service.controls.templates.StatelessTemplate
import android.service.controls.templates.ToggleRangeTemplate
import android.service.controls.templates.ToggleTemplate
import androidx.annotation.RequiresApi
import org.json.JSONObject
import java.util.concurrent.Flow
import java.util.function.Consumer
import kotlin.math.roundToInt

/**
 * ZT Home in the phone's Device Controls panel (Android 11 and later):
 * every device and scene of the account, switched without opening the app.
 * The list comes from the quick controls' copy ([QuickVault]); states and
 * commands go through the app's own adapters in [QuickEngine].
 */
@RequiresApi(Build.VERSION_CODES.R)
class HomeControlsService : ControlsProviderService() {
    private val main = Handler(Looper.getMainLooper())

    override fun createPublisherForAllAvailable(): Flow.Publisher<Control> {
        val catalog = QuickCatalog.read(this)
        val controls = catalog.devices.map { stateless(it) } + catalog.scenes.map { stateless(it) }
        return Flow.Publisher { subscriber ->
            var cancelled = false
            subscriber.onSubscribe(object : Flow.Subscription {
                override fun request(n: Long) {}
                override fun cancel() {
                    cancelled = true
                }
            })
            for (c in controls) if (!cancelled) subscriber.onNext(c)
            if (!cancelled) subscriber.onComplete()
        }
    }

    override fun createPublisherFor(controlIds: List<String>): Flow.Publisher<Control> =
        Flow.Publisher { subscriber ->
            val key = nextKey++
            var cancelled = false
            subscriber.onSubscribe(object : Flow.Subscription {
                override fun request(n: Long) {}
                override fun cancel() {
                    main.post {
                        cancelled = true
                        QuickEngine.unwatch(this@HomeControlsService, key)
                    }
                }
            })
            main.post {
                val catalog = QuickCatalog.read(this)
                val watched = mutableListOf<String>()
                for (id in controlIds) {
                    val scene = catalog.scenes.firstOrNull { it.controlId == id }
                    val device = catalog.devices.firstOrNull { it.id == id }
                    when {
                        scene != null -> subscriber.onNext(stateful(scene))
                        device != null -> {
                            subscriber.onNext(stateful(device, null))
                            watched.add(device.id)
                        }
                        else -> subscriber.onNext(gone(id))
                    }
                }
                if (watched.isNotEmpty()) {
                    QuickEngine.watch(this, key, watched) { id, state ->
                        val device = catalog.devices.firstOrNull { it.id == id }
                        if (!cancelled && device != null) subscriber.onNext(stateful(device, state))
                    }
                }
            }
        }

    override fun performControlAction(
        controlId: String,
        action: ControlAction,
        consumer: Consumer<Int>,
    ) {
        main.post {
            val catalog = QuickCatalog.read(this)
            val scene = catalog.scenes.firstOrNull { it.controlId == controlId }
            if (scene != null && action is CommandAction) {
                return@post QuickEngine.call(this, "scene", mapOf("id" to scene.id)) { failed ->
                    val ok = failed is List<*> && failed.isEmpty()
                    consumer.accept(if (ok) ControlAction.RESPONSE_OK else ControlAction.RESPONSE_FAIL)
                }
            }
            val device = catalog.devices.firstOrNull { it.id == controlId }
                ?: return@post consumer.accept(ControlAction.RESPONSE_FAIL)
            val (capability, value) = when (action) {
                is BooleanAction ->
                    (if ("locked" in device.capabilities) "locked" else "onOff") to action.newState
                is FloatAction -> when (action.templateId.substringAfterLast('.')) {
                    "t" -> "targetTemperature" to ((action.newValue * 2).roundToInt() / 2.0)
                    "b" -> "brightness" to action.newValue.roundToInt()
                    "f" -> "fanSpeed" to action.newValue.roundToInt()
                    else -> "position" to action.newValue.roundToInt()
                }
                else -> return@post consumer.accept(ControlAction.RESPONSE_FAIL)
            }
            QuickEngine.call(
                this,
                "send",
                mapOf("id" to device.id, "capability" to capability, "value" to value),
            ) { ok ->
                consumer.accept(if (ok == true) ControlAction.RESPONSE_OK else ControlAction.RESPONSE_FAIL)
            }
        }
    }

    // --- Building controls -----------------------------------------------

    private fun open(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun stateless(d: QuickDevice): Control =
        Control.StatelessBuilder(d.id, open())
            .setTitle(d.name)
            .setSubtitle(d.room ?: d.home)
            .setStructure(d.home)
            .setZone(d.room ?: d.home)
            .setDeviceType(deviceType(d))
            .build()

    private fun stateless(s: QuickScene): Control =
        Control.StatelessBuilder(s.controlId, open())
            .setTitle(s.name)
            .setSubtitle(getString(R.string.quick_scene))
            .setStructure(s.home)
            .setDeviceType(DeviceTypes.TYPE_ROUTINE)
            .build()

    private fun stateful(s: QuickScene): Control =
        Control.StatefulBuilder(s.controlId, open())
            .setTitle(s.name)
            .setSubtitle(getString(R.string.quick_scene))
            .setStructure(s.home)
            .setDeviceType(DeviceTypes.TYPE_ROUTINE)
            .setStatus(Control.STATUS_OK)
            .setControlTemplate(StatelessTemplate(s.controlId))
            .build()

    private fun gone(id: String): Control =
        Control.StatefulBuilder(id, open())
            .setStatus(Control.STATUS_NOT_FOUND)
            .build()

    /** [state] is null until the device's first reading. */
    private fun stateful(d: QuickDevice, state: Map<*, *>?): Control {
        val values = state?.get("values") as? Map<*, *> ?: emptyMap<Any, Any>()
        val builder = Control.StatefulBuilder(d.id, open())
            .setTitle(d.name)
            .setSubtitle(d.room ?: d.home)
            .setStructure(d.home)
            .setZone(d.room ?: d.home)
            .setDeviceType(deviceType(d))
        when {
            state == null -> builder.setStatus(Control.STATUS_UNKNOWN)
            state["reachable"] != true -> builder
                .setStatus(Control.STATUS_ERROR)
                .setStatusText(getString(R.string.quick_unreachable))
            else -> builder
                .setStatus(Control.STATUS_OK)
                .setStatusText(summary(d, values))
                .setControlTemplate(template(d, values))
        }
        // A door opens only for someone who has unlocked the phone.
        if ("locked" in d.capabilities && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            builder.setAuthRequired(true)
        }
        return builder.build()
    }

    private fun template(d: QuickDevice, values: Map<*, *>): ControlTemplate {
        val caps = d.capabilities
        val on = values["onOff"] == true
        fun num(key: String, fallback: Float) = (values[key] as? Number)?.toFloat() ?: fallback
        fun percent(suffix: String, key: String, min: Float) =
            RangeTemplate("${d.id}.$suffix", min, 100f, num(key, 100f).coerceIn(min, 100f), 1f, "%.0f%%")
        val toggle = ControlButton(on, getString(R.string.quick_on_off))
        return when {
            "locked" in caps -> ToggleTemplate(
                d.id,
                ControlButton(values["locked"] == true, getString(R.string.quick_lock)),
            )
            "targetTemperature" in caps -> {
                val range = RangeTemplate(
                    "${d.id}.t", 5f, 35f, num("targetTemperature", 21f).coerceIn(5f, 35f), 0.5f, "%.1f°C",
                )
                if ("onOff" in caps) ToggleRangeTemplate(d.id, toggle, range) else range
            }
            "brightness" in caps && "onOff" in caps ->
                ToggleRangeTemplate(d.id, toggle, percent("b", "brightness", 1f))
            "fanSpeed" in caps && "onOff" in caps ->
                ToggleRangeTemplate(d.id, toggle, percent("f", "fanSpeed", 1f))
            "position" in caps -> percent("p", "position", 0f)
            "onOff" in caps -> ToggleTemplate(d.id, toggle)
            else -> ControlTemplate.getNoTemplateObject()
        }
    }

    private fun summary(d: QuickDevice, values: Map<*, *>): String {
        val parts = mutableListOf<String>()
        (values["onOff"] as? Boolean)?.let {
            parts.add(getString(if (it) R.string.quick_on else R.string.quick_off))
        }
        (values["locked"] as? Boolean)?.let {
            parts.add(getString(if (it) R.string.quick_locked else R.string.quick_unlocked))
        }
        (values["position"] as? Number)?.let {
            val p = it.toFloat().roundToInt()
            parts.add(
                when {
                    p <= 0 -> getString(R.string.quick_closed)
                    p >= 100 -> getString(R.string.quick_open)
                    else -> getString(R.string.quick_open_percent, p)
                },
            )
        }
        (values["temperature"] as? Number)?.let { parts.add(String.format("%.1f°C", it.toFloat())) }
        (values["humidity"] as? Number)?.let { parts.add("${it.toFloat().roundToInt()}%") }
        if (parts.isEmpty() && "onOff" !in d.capabilities) {
            (values["battery"] as? Number)?.let { parts.add("${it.toFloat().roundToInt()}%") }
        }
        return parts.joinToString(" · ")
    }

    private fun deviceType(d: QuickDevice): Int = when (d.type) {
        "light" -> DeviceTypes.TYPE_LIGHT
        "plug" -> DeviceTypes.TYPE_OUTLET
        "wallSwitch" -> DeviceTypes.TYPE_SWITCH
        "lock" -> DeviceTypes.TYPE_LOCK
        "thermostat" -> DeviceTypes.TYPE_THERMOSTAT
        "blind" -> DeviceTypes.TYPE_BLINDS
        "fan" -> DeviceTypes.TYPE_FAN
        "camera" -> DeviceTypes.TYPE_CAMERA
        else -> DeviceTypes.TYPE_GENERIC_ON_OFF
    }

    companion object {
        private var nextKey = 1
    }
}

class QuickDevice(
    val id: String,
    val name: String,
    val type: String,
    val capabilities: Set<String>,
    val home: String,
    val room: String?,
)

class QuickScene(val id: String, val name: String, val home: String) {
    val controlId get() = "scene:$id"
}

/** The devices and scenes in the quick controls' copy, by home and room. */
class QuickCatalog(val devices: List<QuickDevice>, val scenes: List<QuickScene>) {
    companion object {
        fun read(context: Context): QuickCatalog {
            val text = QuickVault.load(context) ?: return QuickCatalog(emptyList(), emptyList())
            return try {
                parse(JSONObject(text))
            } catch (e: Exception) {
                QuickCatalog(emptyList(), emptyList())
            }
        }

        private fun parse(json: JSONObject): QuickCatalog {
            fun names(key: String): Map<String, String> {
                val list = json.optJSONArray(key) ?: return emptyMap()
                return (0 until list.length()).associate {
                    val item = list.getJSONObject(it)
                    item.optString("id") to item.optString("name")
                }
            }
            val homes = names("homes")
            val rooms = names("rooms")
            val devices = json.optJSONArray("devices")
            val scenes = json.optJSONArray("scenes")
            return QuickCatalog(
                (0 until (devices?.length() ?: 0)).map { i ->
                    val d = devices!!.getJSONObject(i)
                    val caps = d.optJSONArray("capabilities")
                    QuickDevice(
                        id = d.optString("id"),
                        name = d.optString("name"),
                        type = d.optString("type"),
                        capabilities = (0 until (caps?.length() ?: 0)).map { caps!!.optString(it) }.toSet(),
                        home = homes[d.optString("homeId")] ?: "",
                        room = if (d.isNull("roomId")) null else rooms[d.optString("roomId")],
                    )
                }.filter { it.id.isNotEmpty() },
                (0 until (scenes?.length() ?: 0)).map { i ->
                    val s = scenes!!.getJSONObject(i)
                    QuickScene(s.optString("id"), s.optString("name"), homes[s.optString("homeId")] ?: "")
                }.filter { it.id.isNotEmpty() },
            )
        }
    }
}
