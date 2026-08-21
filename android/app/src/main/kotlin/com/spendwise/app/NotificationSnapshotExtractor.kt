package com.spendwise.app

import android.app.Notification
import android.app.NotificationChannel
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService.Ranking
import android.service.notification.NotificationListenerService.RankingMap
import android.service.notification.StatusBarNotification

/** Converts framework notifications into method-channel-safe, deterministic evidence snapshots. */
internal object NotificationSnapshotExtractor {
    fun extract(
        status: StatusBarNotification,
        rankingMap: RankingMap?,
        captureReason: String,
        capturedAt: Long = System.currentTimeMillis(),
    ): CapturedNotificationSnapshot {
        val notification = status.notification
        val extras = notification.extras ?: Bundle.EMPTY
        val statusMetadata = linkedMapOf<String, Any?>(
            "opPackageName" to status.opPkg,
            "notificationId" to status.id,
            "notificationTag" to status.tag,
            "postTime" to status.postTime,
            "groupKey" to status.groupKey,
            "overrideGroupKey" to status.overrideGroupKey,
            "user" to status.user.toString(),
            "userId" to status.user.hashCode(),
            "ongoing" to status.isOngoing,
            "clearable" to status.isClearable,
            "groupSummary" to (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0),
        )
        val content = linkedMapOf<String, Any?>(
            "title" to extras.text(Notification.EXTRA_TITLE),
            "bigTitle" to extras.text(Notification.EXTRA_TITLE_BIG),
            "text" to extras.text(Notification.EXTRA_TEXT),
            "body" to extras.text(Notification.EXTRA_TEXT),
            "bigText" to extras.text(Notification.EXTRA_BIG_TEXT),
            "subText" to extras.text(Notification.EXTRA_SUB_TEXT),
            "summaryText" to extras.text(Notification.EXTRA_SUMMARY_TEXT),
            "infoText" to extras.text(Notification.EXTRA_INFO_TEXT),
            "textLines" to extras.textArray(Notification.EXTRA_TEXT_LINES),
            "template" to extras.text(Notification.EXTRA_TEMPLATE),
            "conversationTitle" to extras.text(Notification.EXTRA_CONVERSATION_TITLE),
            "category" to notification.category,
            "when" to notification.`when`,
            "showWhen" to extras.getBoolean(Notification.EXTRA_SHOW_WHEN, true),
            "channelId" to notification.channelId,
            "group" to notification.group,
            "sortKey" to notification.sortKey,
            "number" to notification.number,
            "priority" to notification.priority,
            "visibility" to notification.visibility,
            "localOnly" to (notification.flags and Notification.FLAG_LOCAL_ONLY != 0),
            "timeoutAfter" to notification.timeoutAfter,
            "groupAlertBehavior" to notification.groupAlertBehavior,
            "messages" to messages(extras, Notification.EXTRA_MESSAGES),
            "historicMessages" to messages(extras, Notification.EXTRA_HISTORIC_MESSAGES),
            "actions" to actions(notification),
        )
        val ranking = ranking(status.key, rankingMap)
        val stable = linkedMapOf<String, Any?>(
            "schemaVersion" to NotificationEventStore.PAYLOAD_SCHEMA_VERSION,
            "notificationKey" to status.key,
            "packageName" to status.packageName,
            "postedAt" to status.postTime,
            "statusBarNotification" to statusMetadata,
            "notification" to content,
            "ranking" to ranking,
            // Compatibility aliases for the existing Flutter ingestion path.
            "title" to content["title"],
            "body" to content["text"],
            "text" to content["text"],
            "bigText" to content["bigText"],
            "subText" to content["subText"],
            "category" to content["category"],
            "channelId" to content["channelId"],
        )
        val contentHash = SnapshotHash.sha256(JsonCodec.canonical(content))
        val snapshotHash = SnapshotHash.sha256(JsonCodec.canonical(stable))
        val payload = LinkedHashMap(stable).apply {
            put("capturedAt", capturedAt)
            put("captureReason", captureReason)
            put("contentHash", contentHash)
            put("snapshotHash", snapshotHash)
        }
        return CapturedNotificationSnapshot(
            notificationKey = status.key,
            packageName = status.packageName,
            postedAt = status.postTime,
            capturedAt = capturedAt,
            captureReason = captureReason,
            contentHash = contentHash,
            snapshotHash = snapshotHash,
            payload = payload,
        )
    }

    private fun ranking(key: String, rankingMap: RankingMap?): Map<String, Any?>? {
        if (rankingMap == null) return null
        val value = Ranking()
        if (!rankingMap.getRanking(key, value)) return null
        return linkedMapOf(
            "rank" to value.rank,
            "importance" to value.importance,
            "ambient" to value.isAmbient,
            "suspended" to value.isSuspended,
            "matchesInterruptionFilter" to value.matchesInterruptionFilter(),
            "lastAudiblyAlertedAt" to value.lastAudiblyAlertedMillis,
            "overrideGroupKey" to value.overrideGroupKey,
            "channel" to channel(value.channel),
            "isConversation" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) value.isConversation else false,
        )
    }

    private fun channel(channel: NotificationChannel?): Map<String, Any?>? {
        channel ?: return null
        return linkedMapOf(
            "id" to channel.id,
            "name" to channel.name?.toString(),
            "description" to channel.description,
            "importance" to channel.importance,
            "group" to channel.group,
            "lockscreenVisibility" to channel.lockscreenVisibility,
            "canBypassDnd" to channel.canBypassDnd(),
            "showLights" to channel.shouldShowLights(),
            "vibrate" to channel.shouldVibrate(),
        )
    }

    @Suppress("DEPRECATION")
    private fun actions(notification: Notification): List<Map<String, Any?>> =
        notification.actions.orEmpty().mapIndexed { index, action ->
            linkedMapOf<String, Any?>(
                "index" to index,
                "title" to action.title?.toString(),
                "iconResourceId" to action.icon,
                "semanticAction" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    action.semanticAction
                } else {
                    Notification.Action.SEMANTIC_ACTION_NONE
                },
                "contextual" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) action.isContextual else false,
                "authenticationRequired" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    action.isAuthenticationRequired
                } else {
                    false
                },
                "remoteInputs" to action.remoteInputs.orEmpty().map { input ->
                    linkedMapOf<String, Any?>(
                        "resultKey" to input.resultKey,
                        "label" to input.label?.toString(),
                        "choices" to input.choices?.map(CharSequence::toString).orEmpty(),
                        "allowFreeFormInput" to input.allowFreeFormInput,
                        "allowedDataTypes" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            input.allowedDataTypes.sorted()
                        } else {
                            emptyList<String>()
                        },
                        "editChoicesBeforeSending" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            input.editChoicesBeforeSending
                        } else {
                            0
                        },
                    )
                },
            )
        }

    private fun messages(extras: Bundle, key: String): List<Map<String, Any?>> {
        val bundles = extras.getParcelableArray(key) ?: return emptyList()
        return Notification.MessagingStyle.Message.getMessagesFromBundleArray(bundles).map { message ->
            val sender = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) message.senderPerson else null
            linkedMapOf(
                "text" to message.text?.toString(),
                "timestamp" to message.timestamp,
                "sender" to (sender?.name?.toString() ?: message.sender?.toString()),
                "senderKey" to sender?.key,
                "senderUri" to sender?.uri,
                "dataMimeType" to message.dataMimeType,
                "dataUri" to message.dataUri?.toString(),
            )
        }
    }

    private fun Bundle.text(key: String): String? = getCharSequence(key)?.toString()
    private fun Bundle.textArray(key: String): List<String> =
        getCharSequenceArray(key)?.map(CharSequence::toString).orEmpty()
}
