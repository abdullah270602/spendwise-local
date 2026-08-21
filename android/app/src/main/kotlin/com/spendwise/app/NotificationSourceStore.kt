package com.spendwise.app

import android.content.Context

internal class NotificationSourceStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    fun configuredPackages(): Set<String> =
        preferences.getStringSet(KEY_PACKAGES, emptySet())?.toSet().orEmpty()

    fun replaceConfiguredPackages(packages: Collection<String>) {
        val normalized = packages.map { it.trim() }.filter { it.isNotEmpty() }.toSet()
        preferences.edit().putStringSet(KEY_PACKAGES, normalized).apply()
    }

    fun isConfigured(packageName: String): Boolean = configuredPackages().contains(packageName)

    fun markListenerConnected(at: Long = System.currentTimeMillis()) {
        preferences.edit()
            .putBoolean(KEY_LISTENER_CONNECTED, true)
            .putLong(KEY_LAST_CONNECTED_AT, at)
            .putLong(KEY_LAST_HEARTBEAT_AT, at)
            .apply()
    }

    fun markListenerDisconnected(at: Long = System.currentTimeMillis()) {
        preferences.edit()
            .putBoolean(KEY_LISTENER_CONNECTED, false)
            .putLong(KEY_LAST_DISCONNECTED_AT, at)
            .putLong(KEY_LAST_HEARTBEAT_AT, at)
            .apply()
    }

    fun markActiveSync(at: Long = System.currentTimeMillis()) {
        preferences.edit()
            .putLong(KEY_LAST_ACTIVE_SYNC_AT, at)
            .putLong(KEY_LAST_HEARTBEAT_AT, at)
            .apply()
    }

    fun markCapture(at: Long = System.currentTimeMillis()) {
        preferences.edit()
            .putLong(KEY_LAST_CAPTURE_AT, at)
            .putLong(KEY_LAST_HEARTBEAT_AT, at)
            .apply()
    }

    fun health(): ListenerHealth = ListenerHealth(
        connected = preferences.getBoolean(KEY_LISTENER_CONNECTED, false),
        lastConnectedAt = preferences.nullableLong(KEY_LAST_CONNECTED_AT),
        lastDisconnectedAt = preferences.nullableLong(KEY_LAST_DISCONNECTED_AT),
        lastActiveSyncAt = preferences.nullableLong(KEY_LAST_ACTIVE_SYNC_AT),
        lastCaptureAt = preferences.nullableLong(KEY_LAST_CAPTURE_AT),
        lastHeartbeatAt = preferences.nullableLong(KEY_LAST_HEARTBEAT_AT),
    )

    fun clear() = preferences.edit().clear().apply()

    companion object {
        private const val PREFERENCES_NAME = "notification_source_config"
        private const val KEY_PACKAGES = "configured_packages"
        private const val KEY_LISTENER_CONNECTED = "listener_connected"
        private const val KEY_LAST_CONNECTED_AT = "last_connected_at"
        private const val KEY_LAST_DISCONNECTED_AT = "last_disconnected_at"
        private const val KEY_LAST_ACTIVE_SYNC_AT = "last_active_sync_at"
        private const val KEY_LAST_CAPTURE_AT = "last_capture_at"
        private const val KEY_LAST_HEARTBEAT_AT = "last_heartbeat_at"
    }

    private fun android.content.SharedPreferences.nullableLong(key: String): Long? =
        if (contains(key)) getLong(key, 0L) else null
}

internal data class ListenerHealth(
    val connected: Boolean,
    val lastConnectedAt: Long?,
    val lastDisconnectedAt: Long?,
    val lastActiveSyncAt: Long?,
    val lastCaptureAt: Long?,
    val lastHeartbeatAt: Long?,
)
