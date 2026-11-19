package dev.sagron.zerotrusthome

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Where a tile in the controls panel lands. Not exported, so only this
 * app's own tiles can start it: another app can't make ZT Home switch a
 * device by sending it an intent. It keeps the tap, opens the app and
 * goes; the app carries the tap out once unlocked.
 */
class QuickTapActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        QuickVault.keepTap(this, intent)
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
        finish()
    }
}
