package dev.sagron.zerotrusthome

import android.app.PendingIntent
import android.content.Context
import android.os.Build
import android.service.controls.Control
import android.service.controls.ControlsProviderService
import android.service.controls.DeviceTypes
import android.service.controls.actions.ControlAction
import android.service.controls.templates.ControlTemplate
import androidx.annotation.RequiresApi
import org.json.JSONObject
import java.util.concurrent.Flow
import java.util.function.Consumer

/**
 * ZT Home in the phone's Device Controls panel (Android 11 and later): the
 * account's devices and scenes, by home and room, from the names in
 * [QuickVault]. How to reach a device stays in the app's vault, so a tile
 * opens ZT Home with the tap ([QuickVault.tapIntent]); once unlocked, the
 * app switches the device or runs the scene.
 */
@RequiresApi(Build.VERSION_CODES.R)
class HomeControlsService : ControlsProviderService() {
    override fun createPublisherForAllAvailable(): Flow.Publisher<Control> {
        val catalog = QuickCatalog.read(this)
        return publish(catalog.devices.map { stateless(it) } + catalog.scenes.map { stateless(it) })
    }

    override fun createPublisherFor(controlIds: List<String>): Flow.Publisher<Control> {
        val catalog = QuickCatalog.read(this)
        return publish(
            controlIds.map { id ->
                val scene = catalog.scenes.firstOrNull { it.controlId == id }
                val device = catalog.devices.firstOrNull { it.id == id }
                when {
                    scene != null -> stateful(scene)
                    device != null -> stateful(device)
                    else -> gone(id)
                }
            },
        )
    }

    /** Tiles have no template: a tap opens the app, never acts here. */
    override fun performControlAction(
        controlId: String,
        action: ControlAction,
        consumer: Consumer<Int>,
    ) = consumer.accept(ControlAction.RESPONSE_FAIL)

    private fun publish(controls: List<Control>): Flow.Publisher<Control> =
        Flow.Publisher { subscriber ->
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

    private fun tap(action: String, id: String): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        QuickVault.tapIntent(this, action, id),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun stateless(d: QuickDevice): Control =
        Control.StatelessBuilder(d.id, tap("toggle", d.id))
            .setTitle(d.name)
            .setSubtitle(d.room ?: d.home)
            .setStructure(d.home)
            .setZone(d.room ?: d.home)
            .setDeviceType(deviceType(d))
            .build()

    private fun stateless(s: QuickScene): Control =
        Control.StatelessBuilder(s.controlId, tap("scene", s.id))
            .setTitle(s.name)
            .setSubtitle(getString(R.string.quick_scene))
            .setStructure(s.home)
            .setDeviceType(DeviceTypes.TYPE_ROUTINE)
            .build()

    private fun stateful(s: QuickScene): Control =
        Control.StatefulBuilder(s.controlId, tap("scene", s.id))
            .setTitle(s.name)
            .setSubtitle(getString(R.string.quick_scene))
            .setStructure(s.home)
            .setDeviceType(DeviceTypes.TYPE_ROUTINE)
            .setStatus(Control.STATUS_OK)
            .setStatusText(getString(R.string.quick_tap_to_open))
            .setControlTemplate(ControlTemplate.getNoTemplateObject())
            .build()

    private fun stateful(d: QuickDevice): Control =
        Control.StatefulBuilder(d.id, tap("toggle", d.id))
            .setTitle(d.name)
            .setSubtitle(d.room ?: d.home)
            .setStructure(d.home)
            .setZone(d.room ?: d.home)
            .setDeviceType(deviceType(d))
            .setStatus(Control.STATUS_OK)
            .setStatusText(getString(R.string.quick_tap_to_open))
            .setControlTemplate(ControlTemplate.getNoTemplateObject())
            .build()

    private fun gone(id: String): Control =
        Control.StatefulBuilder(id, tap("toggle", id))
            .setStatus(Control.STATUS_NOT_FOUND)
            .build()

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
}

class QuickDevice(
    val id: String,
    val name: String,
    val type: String,
    val capabilities: Set<String>,
    val home: String,
    val room: String?,
    val favourite: Boolean,
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
                        favourite = d.optBoolean("favourite"),
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
