package com.spendwise.app

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/** Durable encrypted hand-off queue. Flutter persists a peeked batch before acknowledging it. */
internal class NotificationEventStore(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DATABASE_NAME, null, DATABASE_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        createEventsTable(db)
        createStateTable(db)
        db.execSQL(
            """
            CREATE TABLE observed_sources (
                package_name TEXT PRIMARY KEY,
                last_seen_at INTEGER NOT NULL,
                observation_count INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) migrateVersionOne(db)
    }

    fun enqueue(snapshot: CapturedNotificationSnapshot): NotificationEnqueueResult {
        val encryptedPayload = NotificationFieldCipher.encrypt(JsonCodec.encode(snapshot.payload))
            ?: return NotificationEnqueueResult.ENCRYPTION_FAILED
        val database = writableDatabase
        database.beginTransaction()
        return try {
            val inserted = database.insertWithOnConflict(
                EVENTS_TABLE,
                null,
                ContentValues().apply {
                    put("notification_key", snapshot.notificationKey)
                    put("package_name", snapshot.packageName)
                    put("posted_at", snapshot.postedAt)
                    put("captured_at", snapshot.capturedAt)
                    put("capture_reason", snapshot.captureReason)
                    put("content_hash", snapshot.contentHash)
                    put("snapshot_hash", snapshot.snapshotHash)
                    put("encrypted_payload", encryptedPayload)
                },
                SQLiteDatabase.CONFLICT_IGNORE,
            ) != -1L
            updateObservedSource(database, snapshot, inserted)
            trimQueue(database)
            database.setTransactionSuccessful()
            if (inserted) NotificationEnqueueResult.INSERTED else NotificationEnqueueResult.DUPLICATE
        } finally {
            database.endTransaction()
        }
    }

    fun peek(limit: Int): List<Map<String, Any?>> {
        val events = mutableListOf<Map<String, Any?>>()
        readableDatabase.query(
            EVENTS_TABLE,
            EVENT_COLUMNS,
            null,
            null,
            null,
            null,
            "id ASC",
            limit.coerceIn(1, MAX_PEEK).toString(),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val payload = runCatching {
                    JsonCodec.decode(
                        NotificationFieldCipher.decrypt(cursor.getString(8))
                            ?: error("Missing encrypted notification payload"),
                    )
                }.getOrElse {
                    // Still deliver an ack-able envelope if a Keystore key was invalidated.
                    mapOf("schemaVersion" to PAYLOAD_SCHEMA_VERSION, "payloadUnreadable" to true)
                }
                events += LinkedHashMap<String, Any?>(payload).apply {
                    put("id", cursor.getLong(0))
                    put("notificationKey", cursor.getString(1))
                    put("packageName", cursor.getString(2))
                    put("postedAt", cursor.getLong(3))
                    put("capturedAt", cursor.getLong(4))
                    put("captureReason", cursor.getString(5))
                    put("contentHash", cursor.getString(6))
                    put("snapshotHash", cursor.getString(7))
                }
            }
        }
        return events
    }

    fun acknowledge(ids: Collection<Long>): Int {
        val distinctIds = ids.distinct().take(MAX_ACK)
        if (distinctIds.isEmpty()) return 0
        val placeholders = distinctIds.joinToString(",") { "?" }
        return writableDatabase.delete(
            EVENTS_TABLE,
            "id IN ($placeholders)",
            distinctIds.map(Long::toString).toTypedArray(),
        )
    }

    fun observedSources(): Map<String, ObservedSource> {
        val sources = mutableMapOf<String, ObservedSource>()
        readableDatabase.query(
            "observed_sources",
            arrayOf("package_name", "last_seen_at", "observation_count"),
            null,
            null,
            null,
            null,
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                sources[cursor.getString(0)] = ObservedSource(cursor.getLong(1), cursor.getLong(2))
            }
        }
        return sources
    }

    fun queueHealth(): QueueHealth = readableDatabase.rawQuery(
        """
        SELECT COUNT(*), MIN(captured_at), MAX(captured_at),
               (SELECT evicted_count FROM ingestion_state WHERE id = 1)
        FROM $EVENTS_TABLE
        """.trimIndent(),
        null,
    ).use { cursor ->
        cursor.moveToFirst()
        QueueHealth(
            cursor.getLong(0),
            cursor.nullableLong(1),
            cursor.nullableLong(2),
            MAX_EVENTS,
            cursor.getLong(3),
        )
    }

    fun clear() {
        writableDatabase.beginTransaction()
        try {
            writableDatabase.delete(EVENTS_TABLE, null, null)
            writableDatabase.delete("observed_sources", null, null)
            writableDatabase.execSQL("UPDATE ingestion_state SET evicted_count = 0 WHERE id = 1")
            writableDatabase.setTransactionSuccessful()
        } finally {
            writableDatabase.endTransaction()
        }
    }

    private fun migrateVersionOne(db: SQLiteDatabase) {
        db.execSQL("ALTER TABLE notification_events RENAME TO notification_events_v1")
        db.execSQL("ALTER TABLE observed_sources ADD COLUMN observation_count INTEGER NOT NULL DEFAULT 0")
        createEventsTable(db)
        createStateTable(db)
        db.query(
            "notification_events_v1",
            arrayOf(
                "id", "notification_key", "package_name", "posted_at", "captured_at",
                "title", "body", "big_text", "sub_text", "category", "channel_id",
            ),
            null, null, null, null, "id ASC",
        ).use { cursor -> while (cursor.moveToNext()) migrateLegacyRow(db, cursor) }
        db.execSQL("DROP TABLE notification_events_v1")
    }

    private fun migrateLegacyRow(db: SQLiteDatabase, cursor: Cursor) {
        val notificationKey = cursor.getString(1)
        val packageName = cursor.getString(2)
        val postedAt = cursor.getLong(3)
        val capturedAt = cursor.getLong(4)
        val payload = linkedMapOf<String, Any?>(
            "schemaVersion" to PAYLOAD_SCHEMA_VERSION,
            "notificationKey" to notificationKey,
            "packageName" to packageName,
            "postedAt" to postedAt,
            "capturedAt" to capturedAt,
            "title" to decryptNullable(cursor, 5),
            "body" to decryptNullable(cursor, 6),
            "text" to decryptNullable(cursor, 6),
            "bigText" to decryptNullable(cursor, 7),
            "subText" to decryptNullable(cursor, 8),
            "category" to cursor.nullableString(9),
            "channelId" to cursor.nullableString(10),
        )
        val contentHash = SnapshotHash.sha256(JsonCodec.canonical(payload))
        val snapshotHash = SnapshotHash.sha256("$notificationKey\u0000$postedAt\u0000$contentHash")
        db.insert(EVENTS_TABLE, null, ContentValues().apply {
            put("id", cursor.getLong(0))
            put("notification_key", notificationKey)
            put("package_name", packageName)
            put("posted_at", postedAt)
            put("captured_at", capturedAt)
            put("capture_reason", "migration")
            put("content_hash", contentHash)
            put("snapshot_hash", snapshotHash)
            put("encrypted_payload", NotificationFieldCipher.encrypt(JsonCodec.encode(payload)))
        })
    }

    private fun createEventsTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $EVENTS_TABLE (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                notification_key TEXT NOT NULL,
                package_name TEXT NOT NULL,
                posted_at INTEGER NOT NULL,
                captured_at INTEGER NOT NULL,
                capture_reason TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                snapshot_hash TEXT NOT NULL UNIQUE ON CONFLICT IGNORE,
                encrypted_payload TEXT NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE INDEX event_captured_at_idx ON $EVENTS_TABLE(captured_at)")
        db.execSQL("CREATE INDEX event_key_idx ON $EVENTS_TABLE(notification_key)")
    }

    private fun updateObservedSource(
        db: SQLiteDatabase,
        snapshot: CapturedNotificationSnapshot,
        inserted: Boolean,
    ) {
        var previousLastSeen = 0L
        var previousCount = 0L
        var exists = false
        db.query(
            "observed_sources",
            arrayOf("last_seen_at", "observation_count"),
            "package_name = ?",
            arrayOf(snapshot.packageName),
            null, null, null, "1",
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                exists = true
                previousLastSeen = cursor.getLong(0)
                previousCount = cursor.getLong(1)
            }
        }
        val values = ContentValues().apply {
            put("package_name", snapshot.packageName)
            put("last_seen_at", maxOf(previousLastSeen, snapshot.capturedAt))
            put("observation_count", previousCount + if (inserted) 1 else 0)
        }
        if (exists) {
            db.update("observed_sources", values, "package_name = ?", arrayOf(snapshot.packageName))
        } else {
            db.insert("observed_sources", null, values)
        }
    }

    private fun createStateTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE ingestion_state (
                id INTEGER PRIMARY KEY CHECK(id = 1),
                evicted_count INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
        )
        db.execSQL("INSERT INTO ingestion_state(id, evicted_count) VALUES (1, 0)")
    }

    private fun trimQueue(db: SQLiteDatabase) {
        val removed = db.delete(
            EVENTS_TABLE,
            "id NOT IN (SELECT id FROM $EVENTS_TABLE ORDER BY id DESC LIMIT $MAX_EVENTS)",
            null,
        )
        if (removed > 0) {
            db.execSQL(
                "UPDATE ingestion_state SET evicted_count = evicted_count + ? WHERE id = 1",
                arrayOf(removed),
            )
        }
    }

    private fun decryptNullable(cursor: Cursor, index: Int): String? =
        cursor.nullableString(index)?.let { runCatching { NotificationFieldCipher.decrypt(it) }.getOrNull() }

    private fun Cursor.nullableString(index: Int): String? = if (isNull(index)) null else getString(index)
    private fun Cursor.nullableLong(index: Int): Long? = if (isNull(index)) null else getLong(index)

    companion object {
        private const val DATABASE_NAME = "notification_ingestion.db"
        private const val DATABASE_VERSION = 2
        private const val EVENTS_TABLE = "notification_events"
        private const val MAX_EVENTS = 1_000
        private const val MAX_PEEK = 2_000
        private const val MAX_ACK = 2_000
        internal const val PAYLOAD_SCHEMA_VERSION = 2
        private val EVENT_COLUMNS = arrayOf(
            "id", "notification_key", "package_name", "posted_at", "captured_at",
            "capture_reason", "content_hash", "snapshot_hash", "encrypted_payload",
        )
    }
}

internal enum class NotificationEnqueueResult { INSERTED, DUPLICATE, ENCRYPTION_FAILED }

internal data class CapturedNotificationSnapshot(
    val notificationKey: String,
    val packageName: String,
    val postedAt: Long,
    val capturedAt: Long,
    val captureReason: String,
    val contentHash: String,
    val snapshotHash: String,
    val payload: Map<String, Any?>,
)

internal data class ObservedSource(val lastSeenAt: Long, val observationCount: Long)
internal data class QueueHealth(
    val pendingCount: Long,
    val oldestCapturedAt: Long?,
    val newestCapturedAt: Long?,
    val capacity: Int,
    val evictedCount: Long,
)

internal object SnapshotHash {
    fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}

internal object JsonCodec {
    fun encode(value: Map<String, Any?>): String = JSONObject(value).toString()
    fun decode(value: String): Map<String, Any?> = JSONObject(value).toMap()

    fun canonical(value: Any?): String = when (value) {
        null, JSONObject.NULL -> "null"
        is String, is CharSequence -> JSONObject.quote(value.toString())
        is Number, is Boolean -> value.toString()
        is Map<*, *> -> value.entries.sortedBy { it.key.toString() }
            .joinToString(prefix = "{", postfix = "}") {
                "${JSONObject.quote(it.key.toString())}:${canonical(it.value)}"
            }
        is Iterable<*> -> value.joinToString(prefix = "[", postfix = "]") { canonical(it) }
        is Array<*> -> value.joinToString(prefix = "[", postfix = "]") { canonical(it) }
        is ByteArray -> value.joinToString(prefix = "[", postfix = "]") { it.toString() }
        else -> JSONObject.quote(value.toString())
    }

    private fun JSONObject.toMap(): Map<String, Any?> = keys().asSequence().associateWith { unwrap(opt(it)) }
    private fun JSONArray.toList(): List<Any?> = (0 until length()).map { unwrap(opt(it)) }
    private fun unwrap(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.toMap()
        is JSONArray -> value.toList()
        else -> value
    }
}
