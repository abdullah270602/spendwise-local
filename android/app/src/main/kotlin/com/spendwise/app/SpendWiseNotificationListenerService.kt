package com.spendwise.app

import android.content.ComponentName
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

class SpendWiseNotificationListenerService : NotificationListenerService() {
    /** Bounded serial writer. CallerRunsPolicy provides backpressure instead of dropping evidence. */
    private val writer = ThreadPoolExecutor(
        1,
        1,
        0L,
        TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(WRITER_QUEUE_CAPACITY),
        ThreadPoolExecutor.CallerRunsPolicy(),
    )
    private val sourceStore by lazy { NotificationSourceStore(applicationContext) }
    private val eventStore by lazy { NotificationEventStore(applicationContext) }

    override fun onNotificationPosted(statusBarNotification: StatusBarNotification?) {
        capture(statusBarNotification, runCatching { currentRanking }.getOrNull(), "posted")
    }

    override fun onNotificationPosted(
        statusBarNotification: StatusBarNotification?,
        rankingMap: RankingMap?,
    ) {
        capture(statusBarNotification, rankingMap, "posted")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        activeInstance = this
        sourceStore.markListenerConnected()
        syncActiveNotifications("listener_connected")
    }

    override fun onListenerDisconnected() {
        if (activeInstance === this) activeInstance = null
        sourceStore.markListenerDisconnected()
        requestRebind(ComponentName(this, SpendWiseNotificationListenerService::class.java))
        super.onListenerDisconnected()
    }

    override fun onNotificationRankingUpdate(rankingMap: RankingMap?) {
        super.onNotificationRankingUpdate(rankingMap)
        // Ranking contains useful importance/channel/last-alert evidence and can change after posting.
        syncActiveNotifications("ranking_update", rankingMap)
    }

    private fun syncActiveNotifications(reason: String, rankingMap: RankingMap? = null) {
        val capturedAt = System.currentTimeMillis()
        val active = runCatching { activeNotifications?.toList().orEmpty() }.getOrDefault(emptyList())
        val rankings = rankingMap ?: runCatching { currentRanking }.getOrNull()
        writer.execute {
            active.forEach { status -> captureNow(status, rankings, reason, capturedAt) }
            sourceStore.markActiveSync(capturedAt)
        }
    }

    private fun capture(status: StatusBarNotification?, rankingMap: RankingMap?, reason: String) {
        status ?: return
        val capturedAt = System.currentTimeMillis()
        writer.execute { captureNow(status, rankingMap, reason, capturedAt) }
    }

    private fun captureNow(
        status: StatusBarNotification,
        rankingMap: RankingMap?,
        reason: String,
        capturedAt: Long,
    ): CaptureOutcome {
        if (status.packageName == packageName) return CaptureOutcome.SKIPPED
        if (!sourceStore.isConfigured(status.packageName)) return CaptureOutcome.SKIPPED
        val snapshot = runCatching {
            NotificationSnapshotExtractor.extract(status, rankingMap, reason, capturedAt)
        }.getOrNull() ?: return CaptureOutcome.FAILED
        return when (eventStore.enqueue(snapshot)) {
            NotificationEnqueueResult.INSERTED -> {
                sourceStore.markCapture(capturedAt)
                CaptureOutcome.INSERTED
            }
            NotificationEnqueueResult.DUPLICATE -> CaptureOutcome.DUPLICATE
            NotificationEnqueueResult.ENCRYPTION_FAILED -> CaptureOutcome.FAILED
        }
    }

    private fun scanCurrentTray(): NotificationTrayScanResult {
        val capturedAt = System.currentTimeMillis()
        val active = runCatching { activeNotifications?.toList().orEmpty() }
            .getOrElse { throw IllegalStateException("Android could not read the notification tray", it) }
        val eligible = active.filter {
            it.packageName != packageName && sourceStore.isConfigured(it.packageName)
        }
        val rankings = runCatching { currentRanking }.getOrNull()
        return writer.submit<NotificationTrayScanResult> {
            var queued = 0
            var duplicates = 0
            var failed = 0
            eligible.forEach { status ->
                when (captureNow(status, rankings, "manual_recovery", capturedAt)) {
                    CaptureOutcome.INSERTED -> queued++
                    CaptureOutcome.DUPLICATE -> duplicates++
                    CaptureOutcome.FAILED -> failed++
                    CaptureOutcome.SKIPPED -> Unit
                }
            }
            sourceStore.markActiveSync(capturedAt)
            NotificationTrayScanResult(
                activeCount = active.size,
                eligibleCount = eligible.size,
                queuedCount = queued,
                duplicateCount = duplicates,
                failedCount = failed,
            )
        }.get(MANUAL_SCAN_TIMEOUT_SECONDS, TimeUnit.SECONDS)
    }

    override fun onDestroy() {
        if (activeInstance === this) activeInstance = null
        sourceStore.markListenerDisconnected()
        writer.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val WRITER_QUEUE_CAPACITY = 256
        private const val MANUAL_SCAN_TIMEOUT_SECONDS = 15L

        @Volatile
        private var activeInstance: SpendWiseNotificationListenerService? = null

        fun requestConfiguredSourcesSync(): Boolean {
            val listener = activeInstance ?: return false
            listener.syncActiveNotifications("source_configuration_changed")
            return true
        }

        internal fun requestManualRecoveryScan(): NotificationTrayScanResult? =
            activeInstance?.scanCurrentTray()
    }
}

internal enum class CaptureOutcome { INSERTED, DUPLICATE, FAILED, SKIPPED }

internal data class NotificationTrayScanResult(
    val activeCount: Int,
    val eligibleCount: Int,
    val queuedCount: Int,
    val duplicateCount: Int,
    val failedCount: Int,
)
