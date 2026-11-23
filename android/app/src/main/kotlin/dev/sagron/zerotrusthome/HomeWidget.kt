package dev.sagron.zerotrusthome

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.core.widget.RemoteViewsCompat

/**
 * ZT Home on the home screen: favourites, scenes, then the other devices,
 * by name, from the names in [QuickVault]. Like the controls panel, a tile
 * only opens the app with the tap ([QuickVault.tapIntent]); how to reach a
 * device never leaves the vault. With "Show devices outside the app" off
 * there are no names to show, and the widget says how to turn it on.
 */
class HomeWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) draw(context, manager, id)
    }

    companion object {
        /** Draws every ZT Home widget again: the names changed or went. */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, HomeWidget::class.java))
            for (id in ids) draw(context, manager, id)
        }

        private fun draw(context: Context, manager: AppWidgetManager, id: Int) {
            val shown = QuickVault.load(context) != null
            val catalog = QuickCatalog.read(context)
            val views = RemoteViews(context.packageName, R.layout.home_widget)

            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.home_widget_header, open)
            views.setOnClickPendingIntent(R.id.home_widget_empty, open)
            views.setTextViewText(
                R.id.home_widget_empty_text,
                context.getString(if (shown) R.string.home_widget_empty else R.string.home_widget_locked),
            )
            views.setImageViewResource(
                R.id.home_widget_empty_icon,
                if (shown) R.drawable.ic_zt_widget_add else R.drawable.ic_zt_widget_lock,
            )

            val items = RemoteViewsCompat.RemoteCollectionItems.Builder()
                .setHasStableIds(true)
                .setViewTypeCount(1)
            for (tile in tiles(context, catalog)) {
                val row = RemoteViews(context.packageName, R.layout.home_widget_tile)
                row.setTextViewText(R.id.home_widget_tile_name, tile.name)
                row.setTextViewText(R.id.home_widget_tile_caption, tile.caption)
                // Only the tile's own address: the template below decides
                // where it goes.
                row.setOnClickFillInIntent(
                    R.id.home_widget_tile,
                    Intent().setData(QuickVault.tapIntent(context, tile.action, tile.id).data),
                )
                items.addItem("${tile.action}:${tile.id}".hashCode().toLong(), row)
            }
            RemoteViewsCompat.setRemoteAdapter(context, views, id, R.id.home_widget_grid, items.build())
            views.setEmptyView(R.id.home_widget_grid, R.id.home_widget_empty)
            // Mutable so each tile can fill in its address; the component
            // is fixed (the activity no other app can start), so it is safe.
            views.setPendingIntentTemplate(
                R.id.home_widget_grid,
                PendingIntent.getActivity(
                    context,
                    1,
                    Intent(context, QuickTapActivity::class.java)
                        .setAction(Intent.ACTION_VIEW)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
            manager.updateAppWidget(id, views)
        }

        private class Tile(val action: String, val id: String, val name: String, val caption: String)

        /** Favourites, scenes, then the rest; sensors have nothing to tap. */
        private fun tiles(context: Context, catalog: QuickCatalog): List<Tile> {
            val devices = catalog.devices
                .filter { d -> SWITCHABLE.any { it in d.capabilities } }
                .map { it to Tile("toggle", it.id, it.name, it.room ?: it.home) }
            val scenes = catalog.scenes.map {
                Tile("scene", it.id, it.name, context.getString(R.string.quick_scene))
            }
            return devices.filter { it.first.favourite }.map { it.second } +
                scenes +
                devices.filter { !it.first.favourite }.map { it.second }
        }

        private val SWITCHABLE = setOf("onOff", "position", "locked")
    }
}
