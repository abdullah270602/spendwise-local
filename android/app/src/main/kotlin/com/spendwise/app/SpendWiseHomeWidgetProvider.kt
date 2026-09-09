package com.spendwise.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.widget.RemoteViews

/// The Home-screen widget's Android half.
///
/// Everything it reads comes from [PREFS_NAME], a plain, unencrypted
/// `SharedPreferences` file -- the boundary this widget is not allowed to
/// cross past. The ledger is SQLCipher-encrypted with its key in the Android
/// keystore, this provider runs in a process the app is not always alive in,
/// and there is no version of "decrypt it here" that is not a worse idea
/// than simply never handing this file anything worth protecting the way the
/// ledger is protected. What lands here is a kept fraction, a flag, a second
/// fraction and a second flag for the one style that draws a third branch,
/// and three colours the user already chose in Settings -- see
/// `WidgetBridge` on the Dart side for the one place that boundary is
/// crossed, and `SpendWiseHomeWidgetRenderer` for the only thing done with
/// what crosses.
///
/// There is no periodic refresh here (`updatePeriodMillis="0"` in the
/// provider's XML), and this class never schedules one of its own: the app
/// pushes a redraw through [publish] exactly when the ledger produces a
/// different picture, and every other update this class ever performs
/// -- [onUpdate], [onAppWidgetOptionsChanged] -- simply redraws whatever was
/// last published, at whatever size Android is now asking for. A phone that
/// has not opened SpendWise in a week costs this widget nothing: no alarm,
/// no wake, no network it could not reach even if it tried.
class SpendWiseHomeWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        // A resize is not a data change -- it is redrawn from the same
        // stored fraction and colours, at the new size Android is now
        // reporting.
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    private fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val prefs = prefs(context)
        val hasData = prefs.getBoolean(KEY_HAS_DATA, false)
        val keptFraction = prefs.getFloat(KEY_KEPT_FRACTION, 0f).coerceIn(0f, 1f)
        val hasSavedBranch = prefs.getBoolean(KEY_HAS_SAVED_BRANCH, false)
        val savedFraction = prefs.getFloat(KEY_SAVED_FRACTION, 0f).coerceIn(0f, 1f)
        val keepColor = prefs.getInt(KEY_KEEP_COLOR, context.getColor(R.color.spendwise_keep))
        val spendColor = prefs.getInt(KEY_SPEND_COLOR, context.getColor(R.color.spendwise_spend))
        val mineColor = prefs.getInt(KEY_MINE_COLOR, context.getColor(R.color.spendwise_mine))

        val density = context.resources.displayMetrics.density
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        // minWidth/minHeight are what Android actually promises this widget
        // at its current cell size; the max* pair only bounds how far a
        // resizable widget could still grow, which is not what is on screen
        // right now.
        val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, DEFAULT_WIDTH_DP)
            .takeIf { it > 0 } ?: DEFAULT_WIDTH_DP
        val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, DEFAULT_HEIGHT_DP)
            .takeIf { it > 0 } ?: DEFAULT_HEIGHT_DP
        // Capped well above anything a home-screen widget is actually laid
        // out at, so a launcher that reports a wildly generous size cannot
        // make this allocate an unreasonable bitmap.
        val widthPx = (widthDp * density).toInt().coerceIn(1, MAX_DIMENSION_PX)
        val heightPx = (heightDp * density).toInt().coerceIn(1, MAX_DIMENSION_PX)

        val bitmap = SpendWiseHomeWidgetRenderer.render(
            widthPx = widthPx,
            heightPx = heightPx,
            densityDpToPx = density,
            hasData = hasData,
            keptFraction = keptFraction,
            hasSavedBranch = hasSavedBranch,
            savedFraction = savedFraction,
            keepColor = keepColor,
            spendColor = spendColor,
            mineColor = mineColor,
        )

        val views = RemoteViews(context.packageName, R.layout.spendwise_home_widget)
        views.setImageViewBitmap(R.id.spendwise_home_widget_shape, bitmap)
        views.setOnClickPendingIntent(R.id.spendwise_home_widget_root, openAppIntent(context))
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    /// Opens straight to Home -- the same screen the shape is a picture of,
    /// and the app's default screen, so no deep link is needed to get there.
    private fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        // FLAG_IMMUTABLE: nothing about this PendingIntent should ever be
        // filled in by whoever the launcher hands it to -- it opens the app
        // and does nothing else, so there is nothing to fill in.
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    companion object {
        const val PREFS_NAME = "spendwise_home_widget"
        const val KEY_HAS_DATA = "has_data"
        const val KEY_KEPT_FRACTION = "kept_fraction"
        const val KEY_HAS_SAVED_BRANCH = "has_saved_branch"
        const val KEY_SAVED_FRACTION = "saved_fraction"
        const val KEY_KEEP_COLOR = "keep_color"
        const val KEY_SPEND_COLOR = "spend_color"
        const val KEY_MINE_COLOR = "mine_color"

        private const val DEFAULT_WIDTH_DP = 110
        private const val DEFAULT_HEIGHT_DP = 80
        private const val MAX_DIMENSION_PX = 2000

        private fun prefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        /// The one entry point the Dart side calls, through
        /// `MainActivity`'s method channel. Stores exactly the fields
        /// [WidgetBridge] sends -- see the class comment above for why
        /// nothing else is ever asked for -- then redraws every instance of
        /// this widget the user has actually placed. A ledger change with no
        /// widget on any home screen costs one `SharedPreferences` write and
        /// nothing else: `getAppWidgetIds` returns empty and the loop below
        /// never runs.
        fun publish(
            context: Context,
            hasData: Boolean,
            keptFraction: Float,
            hasSavedBranch: Boolean,
            savedFraction: Float,
            keepColor: Int,
            spendColor: Int,
            mineColor: Int,
        ) {
            prefs(context).edit()
                .putBoolean(KEY_HAS_DATA, hasData)
                .putFloat(KEY_KEPT_FRACTION, keptFraction)
                .putBoolean(KEY_HAS_SAVED_BRANCH, hasSavedBranch)
                .putFloat(KEY_SAVED_FRACTION, savedFraction)
                .putInt(KEY_KEEP_COLOR, keepColor)
                .putInt(KEY_SPEND_COLOR, spendColor)
                .putInt(KEY_MINE_COLOR, mineColor)
                .apply()

            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(android.content.ComponentName(context, SpendWiseHomeWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val provider = SpendWiseHomeWidgetProvider()
            for (id in ids) {
                provider.updateWidget(context, manager, id)
            }
        }
    }
}
