package com.spendwise.app

import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.graphics.drawable.Drawable
import android.provider.Settings
import java.io.ByteArrayOutputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_CHANNEL,
        ).setMethodCallHandler(::handleNotificationMethod)
    }

    private fun handleNotificationMethod(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "openNotificationAccessSettings" -> {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                "isNotificationAccessGranted" -> result.success(isNotificationAccessGranted())
                "peekQueuedEvents" -> {
                    val requestedLimit = call.argument<Number>("limit")?.toInt() ?: 500
                    val limit = requestedLimit.coerceIn(1, 2_000)
                    NotificationEventStore(applicationContext).use {
                        result.success(it.peek(limit))
                    }
                }
                "ackQueuedEvents" -> {
                    val ids = call.argument<List<Number>>("ids").orEmpty().map { it.toLong() }
                    NotificationEventStore(applicationContext).use {
                        result.success(it.acknowledge(ids))
                    }
                }
                "listNotificationSources" -> result.success(listNotificationSources())
                "getNotificationIngestionHealth" -> result.success(notificationIngestionHealth())
                "setNotificationSources" -> {
                    val packages = call.argument<List<String>>("packageNames").orEmpty()
                    NotificationSourceStore(applicationContext).replaceConfiguredPackages(packages)
                    SpendWiseNotificationListenerService.requestConfiguredSourcesSync()
                    result.success(true)
                }
                "clearNotificationData" -> {
                    NotificationEventStore(applicationContext).use { it.clear() }
                    NotificationSourceStore(applicationContext).clear()
                    NotificationFieldCipher.deleteKey()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("notification_bridge_error", error.message, null)
        }
    }

    private fun isNotificationAccessGranted(): Boolean {
        val component = ComponentName(this, SpendWiseNotificationListenerService::class.java)
        return Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?.split(':')
            ?.mapNotNull { ComponentName.unflattenFromString(it) }
            ?.any { it == component } == true
    }

    @Suppress("DEPRECATION")
    private fun listNotificationSources(): List<Map<String, Any?>> {
        val sourceStore = NotificationSourceStore(applicationContext)
        val configured = sourceStore.configuredPackages()
        val observed = NotificationEventStore(applicationContext).use { it.observedSources() }
        val accessGranted = isNotificationAccessGranted()
        val listenerHealth = sourceStore.health()
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = packageManager.queryIntentActivities(launcherIntent, 0)
            .asSequence()
            .map { it.activityInfo.applicationInfo }
            .distinctBy { it.packageName }
            .filter { it.packageName != packageName }
            .map { applicationInfo ->
                val observation = observed[applicationInfo.packageName]
                mapOf<String, Any?>(
                    "packageName" to applicationInfo.packageName,
                    "label" to packageManager.getApplicationLabel(applicationInfo).toString(),
                    "configured" to configured.contains(applicationInfo.packageName),
                    "lastObservedAt" to observation?.lastSeenAt,
                    "observationCount" to observation?.observationCount,
                    "iconPng" to renderIconPng(applicationInfo.loadIcon(packageManager)),
                    "iconCacheKey" to iconCacheKey(applicationInfo.packageName),
                    "health" to mapOf(
                        "installed" to true,
                        "enabled" to applicationInfo.enabled,
                        "notificationAccessGranted" to accessGranted,
                        "listenerConnected" to listenerHealth.connected,
                        "lastListenerHeartbeatAt" to listenerHealth.lastHeartbeatAt,
                    ),
                )
            }
            .sortedBy { it["label"].toString().lowercase() }
            .toMutableList()

        // Preserve an observed/configured package even if it no longer exposes a launcher activity.
        val listed = apps.mapTo(mutableSetOf()) { it["packageName"] as String }
        (configured + observed.keys).filterNot(listed::contains).forEach { packageName ->
            val applicationInfo = runCatching { packageManager.getApplicationInfo(packageName, 0) }.getOrNull()
            val label = applicationInfo?.let { packageManager.getApplicationLabel(it).toString() } ?: packageName
            val observation = observed[packageName]
            apps += mapOf(
                "packageName" to packageName,
                "label" to label,
                "configured" to configured.contains(packageName),
                "lastObservedAt" to observation?.lastSeenAt,
                "observationCount" to observation?.observationCount,
                "iconPng" to applicationInfo?.loadIcon(packageManager)?.let(::renderIconPng),
                "iconCacheKey" to applicationInfo?.let { iconCacheKey(packageName) },
                "health" to mapOf(
                    "installed" to (applicationInfo != null),
                    "enabled" to (applicationInfo?.enabled == true),
                    "notificationAccessGranted" to accessGranted,
                    "listenerConnected" to listenerHealth.connected,
                    "lastListenerHeartbeatAt" to listenerHealth.lastHeartbeatAt,
                ),
            )
        }
        return apps
    }

    private fun notificationIngestionHealth(): Map<String, Any?> {
        val listener = NotificationSourceStore(applicationContext).health()
        val queue = NotificationEventStore(applicationContext).use { it.queueHealth() }
        return mapOf(
            "notificationAccessGranted" to isNotificationAccessGranted(),
            "listenerConnected" to listener.connected,
            "lastConnectedAt" to listener.lastConnectedAt,
            "lastDisconnectedAt" to listener.lastDisconnectedAt,
            "lastActiveSyncAt" to listener.lastActiveSyncAt,
            "lastCaptureAt" to listener.lastCaptureAt,
            "lastHeartbeatAt" to listener.lastHeartbeatAt,
            "pendingCount" to queue.pendingCount,
            "oldestPendingCapturedAt" to queue.oldestCapturedAt,
            "newestPendingCapturedAt" to queue.newestCapturedAt,
            "queueCapacity" to queue.capacity,
            "evictedEvidenceCount" to queue.evictedCount,
            "payloadSchemaVersion" to NotificationEventStore.PAYLOAD_SCHEMA_VERSION,
        )
    }

    private fun iconCacheKey(packageName: String): String = runCatching {
        val packageInfo = packageManager.getPackageInfo(packageName, 0)
        "$packageName:${packageInfo.lastUpdateTime}"
    }.getOrDefault(packageName)

    private fun renderIconPng(drawable: Drawable): ByteArray? = runCatching {
        val size = ICON_SIZE_PX
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val oldBounds = Rect(drawable.bounds)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        drawable.bounds = oldBounds
        ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            bitmap.recycle()
            output.toByteArray()
        }
    }.getOrNull()

    companion object {
        const val NOTIFICATION_CHANNEL = "com.spendwise.app/notifications"
        private const val ICON_SIZE_PX = 64
    }
}
