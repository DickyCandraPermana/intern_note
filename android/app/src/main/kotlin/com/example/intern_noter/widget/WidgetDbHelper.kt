package com.example.intern_noter.widget

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONException
import java.util.Calendar
import java.util.Locale
import kotlin.math.max

object IndonesianDates {
    private val daysFull = arrayOf(
        "Minggu",
        "Senin",
        "Selasa",
        "Rabu",
        "Kamis",
        "Jumat",
        "Sabtu",
    )
    private val daysShort = arrayOf(
        "Min",
        "Sen",
        "Sel",
        "Rab",
        "Kam",
        "Jum",
        "Sab",
    )
    private val monthsShort = arrayOf(
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "Mei",
        "Jun",
        "Jul",
        "Agu",
        "Sep",
        "Okt",
        "Nov",
        "Des",
    )
    private val isoPrefixRegex = Regex("^(\\d{4}-\\d{2}-\\d{2})")

    fun todayIso(cal: Calendar = Calendar.getInstance()): String {
        return String.format(
            Locale.US,
            "%04d-%02d-%02d",
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH),
        )
    }

    fun normalizeIsoDate(raw: String): String {
        val trimmed = raw.trim()
        val match = isoPrefixRegex.find(trimmed)
        if (match != null) {
            return match.groupValues[1]
        }
        return if (trimmed.length >= 10) trimmed.substring(0, 10) else trimmed
    }

    fun formatShortDate(cal: Calendar = Calendar.getInstance()): String {
        val dayIndex = (cal.get(Calendar.DAY_OF_WEEK) - 1).coerceIn(0, daysShort.lastIndex)
        val monthIndex = cal.get(Calendar.MONTH).coerceIn(0, monthsShort.lastIndex)
        val dayOfMonth = cal.get(Calendar.DAY_OF_MONTH)
        return "${daysShort[dayIndex]}, $dayOfMonth ${monthsShort[monthIndex]}"
    }

    fun formatLongDayDate(cal: Calendar = Calendar.getInstance()): String {
        val dayIndex = (cal.get(Calendar.DAY_OF_WEEK) - 1).coerceIn(0, daysFull.lastIndex)
        val monthIndex = cal.get(Calendar.MONTH).coerceIn(0, monthsShort.lastIndex)
        val dayOfMonth = cal.get(Calendar.DAY_OF_MONTH)
        val year = cal.get(Calendar.YEAR)
        return "${daysFull[dayIndex]}, $dayOfMonth ${monthsShort[monthIndex]} $year"
    }
}

data class WidgetActivityLine(
    val id: Long,
    val modul: String,
    val project: String,
    val description: String,
    val sortOrder: Int,
)

data class TodaySummary(
    val dateIso: String,
    val totalHours: Double,
    val lines: List<WidgetActivityLine>,
)

data class QuickNoteTag(
    val modul: String,
    val project: String,
) {
    fun displayLabel(): String {
        val m = modul.trim()
        val p = project.trim()
        return when {
            m.isNotEmpty() && p.isNotEmpty() -> "$m / $p"
            m.isNotEmpty() -> m
            p.isNotEmpty() -> p
            else -> "Tanpa Tag"
        }
    }
}

data class QuickNoteContext(
    val defaultBaseHours: Double,
    val defaultTag: QuickNoteTag?,
    val recentTags: List<QuickNoteTag>,
    val quickPresets: List<String>,
)

class WidgetDbHelper(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        const val DATABASE_NAME = "intern_noter.db"
        const val DATABASE_VERSION = 3
        const val DEFAULT_QUICK_PRESETS_JSON =
            """["Daily Scrum 7E","Join Daily Stand-Up CK"]"""
        val DEFAULT_QUICK_PRESETS = listOf(
            "Daily Scrum 7E",
            "Join Daily Stand-Up CK",
        )
    }

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.setForeignKeyConstraintsEnabled(true)
        db.enableWriteAheadLogging()
        db.rawQuery("PRAGMA busy_timeout = 3000", null).use { cursor ->
            cursor.moveToFirst()
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        createTablesV3(db)
        ensureDefaultGlobalConfig(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            upgradeFromV1(db)
        }
        if (oldVersion < 3) {
            upgradeToV3(db)
        }
    }

    private fun createTablesV3(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS daily_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              date TEXT NOT NULL UNIQUE,
              base_hours REAL NOT NULL,
              overwork_hours REAL NOT NULL
            )
            """.trimIndent(),
        )

        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS activity_lines (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              daily_log_id INTEGER NOT NULL,
              modul TEXT NOT NULL,
              project TEXT NOT NULL,
              description TEXT NOT NULL,
              sort_order INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (daily_log_id) REFERENCES daily_logs(id) ON DELETE CASCADE
            )
            """.trimIndent(),
        )

        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS global_config (
              id INTEGER PRIMARY KEY,
              pic_consultant TEXT NOT NULL,
              role TEXT NOT NULL,
              created_by_name TEXT NOT NULL,
              approved_by_name TEXT NOT NULL,
              approved_by_lead_name TEXT NOT NULL,
              default_base_hours REAL NOT NULL,
              theme_mode TEXT NOT NULL DEFAULT 'system',
              cutoff_day INTEGER NOT NULL DEFAULT 24,
              default_modul TEXT NOT NULL DEFAULT '',
              default_project TEXT NOT NULL DEFAULT '',
              quick_presets TEXT NOT NULL DEFAULT '["Daily Scrum 7E","Join Daily Stand-Up CK"]',
              include_signature INTEGER NOT NULL DEFAULT 1
            )
            """.trimIndent(),
        )
    }

    private fun ensureDefaultGlobalConfig(db: SQLiteDatabase) {
        val values = ContentValues().apply {
            put("id", 1)
            put("pic_consultant", "")
            put("role", "")
            put("created_by_name", "")
            put("approved_by_name", "")
            put("approved_by_lead_name", "")
            put("default_base_hours", 8.0)
            put("theme_mode", "system")
            put("cutoff_day", 24)
            put("default_modul", "")
            put("default_project", "")
            put("quick_presets", DEFAULT_QUICK_PRESETS_JSON)
            put("include_signature", 1)
        }
        db.insertWithOnConflict("global_config", null, values, SQLiteDatabase.CONFLICT_IGNORE)
    }

    private fun tableExists(db: SQLiteDatabase, tableName: String): Boolean {
        db.rawQuery(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
            arrayOf(tableName),
        ).use { cursor ->
            return cursor.moveToFirst()
        }
    }

    private fun hasColumn(db: SQLiteDatabase, tableName: String, columnName: String): Boolean {
        db.rawQuery("PRAGMA table_info($tableName)", null).use { cursor ->
            val nameIdx = cursor.getColumnIndex("name")
            while (cursor.moveToNext()) {
                if (nameIdx >= 0 && cursor.getString(nameIdx) == columnName) {
                    return true
                }
            }
        }
        return false
    }

    private fun upgradeFromV1(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS daily_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              date TEXT NOT NULL UNIQUE,
              base_hours REAL NOT NULL,
              overwork_hours REAL NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS activity_lines (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              daily_log_id INTEGER NOT NULL,
              modul TEXT NOT NULL,
              project TEXT NOT NULL,
              description TEXT NOT NULL,
              FOREIGN KEY (daily_log_id) REFERENCES daily_logs(id) ON DELETE CASCADE
            )
            """.trimIndent(),
        )

        if (tableExists(db, "activities")) {
            data class OldActivity(
                val date: String,
                val modul: String,
                val project: String,
                val activity: String,
                val hours: Double,
            )

            val grouped = linkedMapOf<String, MutableList<OldActivity>>()
            db.rawQuery(
                "SELECT date, modul, project, activity, hours FROM activities ORDER BY id ASC",
                null,
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val rawDate = cursor.getString(0) ?: ""
                    val dateKey = IndonesianDates.normalizeIsoDate(rawDate)
                    val item = OldActivity(
                        date = dateKey,
                        modul = cursor.getString(1) ?: "",
                        project = cursor.getString(2) ?: "",
                        activity = cursor.getString(3) ?: "",
                        hours = if (cursor.isNull(4)) 0.0 else cursor.getDouble(4),
                    )
                    grouped.getOrPut(dateKey) { mutableListOf() }.add(item)
                }
            }

            for ((dateKey, items) in grouped) {
                val totalHours = items.sumOf { it.hours }
                val base = if (totalHours > 8.0) 8.0 else totalHours
                val over = if (totalHours > 8.0) totalHours - 8.0 else 0.0
                val logValues = ContentValues().apply {
                    put("date", dateKey)
                    put("base_hours", base)
                    put("overwork_hours", over)
                }
                val logId = db.insert("daily_logs", null, logValues)
                if (logId != -1L) {
                    for (item in items) {
                        val lineValues = ContentValues().apply {
                            put("daily_log_id", logId)
                            put("modul", item.modul)
                            put("project", item.project)
                            put("description", item.activity)
                        }
                        db.insert("activity_lines", null, lineValues)
                    }
                }
            }

            db.execSQL("ALTER TABLE activities RENAME TO old_activities")
        }

        if (tableExists(db, "global_config")) {
            if (!hasColumn(db, "global_config", "approved_by_lead_name")) {
                db.execSQL(
                    "ALTER TABLE global_config ADD COLUMN approved_by_lead_name TEXT DEFAULT ''",
                )
            }
            if (!hasColumn(db, "global_config", "default_base_hours")) {
                db.execSQL(
                    "ALTER TABLE global_config ADD COLUMN default_base_hours REAL DEFAULT 8.0",
                )
            }
        }
    }

    private fun upgradeToV3(db: SQLiteDatabase) {
        if (!tableExists(db, "daily_logs") || !tableExists(db, "activity_lines") || !tableExists(db, "global_config")) {
            createTablesV3(db)
        }

        if (!hasColumn(db, "activity_lines", "sort_order")) {
            db.execSQL("ALTER TABLE activity_lines ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0")
        }

        if (!hasColumn(db, "global_config", "theme_mode")) {
            db.execSQL("ALTER TABLE global_config ADD COLUMN theme_mode TEXT NOT NULL DEFAULT 'system'")
        }
        if (!hasColumn(db, "global_config", "cutoff_day")) {
            db.execSQL("ALTER TABLE global_config ADD COLUMN cutoff_day INTEGER NOT NULL DEFAULT 24")
        }
        if (!hasColumn(db, "global_config", "default_modul")) {
            db.execSQL("ALTER TABLE global_config ADD COLUMN default_modul TEXT NOT NULL DEFAULT ''")
        }
        if (!hasColumn(db, "global_config", "default_project")) {
            db.execSQL("ALTER TABLE global_config ADD COLUMN default_project TEXT NOT NULL DEFAULT ''")
        }
        if (!hasColumn(db, "global_config", "quick_presets")) {
            db.execSQL(
                "ALTER TABLE global_config ADD COLUMN quick_presets TEXT NOT NULL DEFAULT '[\"Daily Scrum 7E\",\"Join Daily Stand-Up CK\"]'",
            )
        }
        if (!hasColumn(db, "global_config", "include_signature")) {
            db.execSQL("ALTER TABLE global_config ADD COLUMN include_signature INTEGER NOT NULL DEFAULT 1")
        }

        ensureDefaultGlobalConfig(db)

        data class RawLog(
            val id: Long,
            val rawDate: String,
            val baseHours: Double,
            val overworkHours: Double,
        )

        val groupedLogs = linkedMapOf<String, MutableList<RawLog>>()
        db.rawQuery(
            "SELECT id, date, base_hours, overwork_hours FROM daily_logs ORDER BY id ASC",
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                val rawDate = cursor.getString(1) ?: ""
                val baseHours = if (cursor.isNull(2)) 8.0 else cursor.getDouble(2)
                val overworkHours = if (cursor.isNull(3)) 0.0 else cursor.getDouble(3)
                val normalized = IndonesianDates.normalizeIsoDate(rawDate)
                groupedLogs.getOrPut(normalized) { mutableListOf() }.add(
                    RawLog(id, rawDate, baseHours, overworkHours),
                )
            }
        }

        for ((normalizedDate, group) in groupedLogs) {
            val canonical = group.first()
            var maxBaseHours = canonical.baseHours
            var sumOverworkHours = canonical.overworkHours

            for (i in 1 until group.size) {
                val duplicate = group[i]
                maxBaseHours = max(maxBaseHours, duplicate.baseHours)
                sumOverworkHours += duplicate.overworkHours

                val reassign = ContentValues().apply {
                    put("daily_log_id", canonical.id)
                }
                db.update(
                    "activity_lines",
                    reassign,
                    "daily_log_id = ?",
                    arrayOf(duplicate.id.toString()),
                )
                db.delete(
                    "daily_logs",
                    "id = ?",
                    arrayOf(duplicate.id.toString()),
                )
            }

            if (group.size > 1 || canonical.rawDate != normalizedDate) {
                val updateValues = ContentValues().apply {
                    put("date", normalizedDate)
                    put("base_hours", maxBaseHours)
                    put("overwork_hours", sumOverworkHours)
                }
                db.update(
                    "daily_logs",
                    updateValues,
                    "id = ?",
                    arrayOf(canonical.id.toString()),
                )
            }
        }

        val lineOrderUpdates = mutableListOf<Pair<Long, Int>>()
        val nextOrderByLog = hashMapOf<Long, Int>()
        db.rawQuery(
            "SELECT id, daily_log_id FROM activity_lines ORDER BY daily_log_id ASC, id ASC",
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val lineId = cursor.getLong(0)
                val logId = cursor.getLong(1)
                val order = nextOrderByLog[logId] ?: 0
                nextOrderByLog[logId] = order + 1
                lineOrderUpdates.add(lineId to order)
            }
        }
        for ((lineId, order) in lineOrderUpdates) {
            val values = ContentValues().apply {
                put("sort_order", order)
            }
            db.update("activity_lines", values, "id = ?", arrayOf(lineId.toString()))
        }
    }

    fun getTodaySummary(todayIso: String = IndonesianDates.todayIso()): TodaySummary {
        val normalizedDate = IndonesianDates.normalizeIsoDate(todayIso)
        val db = readableDatabase

        var logId: Long? = null
        var totalHours = 0.0
        db.rawQuery(
            "SELECT id, base_hours, overwork_hours FROM daily_logs WHERE date = ? LIMIT 1",
            arrayOf(normalizedDate),
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                logId = cursor.getLong(0)
                val baseHours = if (cursor.isNull(1)) 0.0 else cursor.getDouble(1)
                val overworkHours = if (cursor.isNull(2)) 0.0 else cursor.getDouble(2)
                totalHours = baseHours + overworkHours
            }
        }

        if (logId == null) {
            return TodaySummary(
                dateIso = normalizedDate,
                totalHours = 0.0,
                lines = emptyList(),
            )
        }

        val lines = mutableListOf<WidgetActivityLine>()
        db.rawQuery(
            """
            SELECT id, modul, project, description, sort_order
            FROM activity_lines
            WHERE daily_log_id = ?
            ORDER BY sort_order ASC, id ASC
            """.trimIndent(),
            arrayOf(logId.toString()),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                lines.add(
                    WidgetActivityLine(
                        id = cursor.getLong(0),
                        modul = cursor.getString(1) ?: "",
                        project = cursor.getString(2) ?: "",
                        description = cursor.getString(3) ?: "",
                        sortOrder = if (cursor.isNull(4)) 0 else cursor.getInt(4),
                    ),
                )
            }
        }

        return TodaySummary(
            dateIso = normalizedDate,
            totalHours = totalHours,
            lines = lines,
        )
    }

    fun getQuickNoteContext(): QuickNoteContext {
        val db = readableDatabase

        var defaultBaseHours = 8.0
        var defaultModul = ""
        var defaultProject = ""
        var rawQuickPresets: String? = null

        db.rawQuery(
            """
            SELECT default_base_hours, default_modul, default_project, quick_presets
            FROM global_config
            WHERE id = 1
            LIMIT 1
            """.trimIndent(),
            null,
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                val base = if (cursor.isNull(0)) 8.0 else cursor.getDouble(0)
                defaultBaseHours = if (base > 0.0) base else 8.0
                defaultModul = (cursor.getString(1) ?: "").trim()
                defaultProject = (cursor.getString(2) ?: "").trim()
                rawQuickPresets = cursor.getString(3)
            }
        }

        val distinctRecent = linkedSetOf<QuickNoteTag>()
        db.rawQuery(
            """
            SELECT modul, project
            FROM activity_lines
            WHERE TRIM(modul) != '' OR TRIM(project) != ''
            ORDER BY id DESC
            LIMIT 40
            """.trimIndent(),
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val m = (cursor.getString(0) ?: "").trim()
                val p = (cursor.getString(1) ?: "").trim()
                if (m.isNotEmpty() || p.isNotEmpty()) {
                    distinctRecent.add(QuickNoteTag(m, p))
                }
            }
        }

        val configuredDefault =
            if (defaultModul.isNotEmpty() || defaultProject.isNotEmpty()) {
                QuickNoteTag(defaultModul, defaultProject)
            } else {
                null
            }

        val defaultTag = distinctRecent.firstOrNull() ?: configuredDefault
        val combinedTags = linkedSetOf<QuickNoteTag>()
        if (defaultTag != null) {
            combinedTags.add(defaultTag)
        }
        combinedTags.addAll(distinctRecent)
        if (configuredDefault != null) {
            combinedTags.add(configuredDefault)
        }

        return QuickNoteContext(
            defaultBaseHours = defaultBaseHours,
            defaultTag = defaultTag,
            recentTags = combinedTags.take(4),
            quickPresets = parseQuickPresets(rawQuickPresets),
        )
    }

    fun insertQuickNote(
        todayIso: String = IndonesianDates.todayIso(),
        description: String,
        modul: String = "",
        project: String = "",
    ): Long {
        val trimmedDescription = description.trim()
        require(trimmedDescription.isNotEmpty()) {
            "Quick note description cannot be empty."
        }

        val normalizedDate = IndonesianDates.normalizeIsoDate(todayIso)
        val trimmedModul = modul.trim()
        val trimmedProject = project.trim()
        val db = writableDatabase

        db.beginTransaction()
        try {
            var logId: Long? = null
            db.rawQuery(
                "SELECT id FROM daily_logs WHERE date = ? LIMIT 1",
                arrayOf(normalizedDate),
            ).use { cursor ->
                if (cursor.moveToFirst()) {
                    logId = cursor.getLong(0)
                }
            }

            if (logId == null) {
                var baseHours = 8.0
                db.rawQuery(
                    "SELECT default_base_hours FROM global_config WHERE id = 1 LIMIT 1",
                    null,
                ).use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) {
                        val candidate = cursor.getDouble(0)
                        if (candidate > 0.0) {
                            baseHours = candidate
                        }
                    }
                }

                val logValues = ContentValues().apply {
                    put("date", normalizedDate)
                    put("base_hours", baseHours)
                    put("overwork_hours", 0.0)
                }
                logId = db.insertOrThrow("daily_logs", null, logValues)
            }

            var nextOrder = 0
            db.rawQuery(
                "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM activity_lines WHERE daily_log_id = ?",
                arrayOf(logId.toString()),
            ).use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) {
                    nextOrder = cursor.getInt(0)
                }
            }

            val lineValues = ContentValues().apply {
                put("daily_log_id", logId)
                put("modul", trimmedModul)
                put("project", trimmedProject)
                put("description", trimmedDescription)
                put("sort_order", nextOrder)
            }
            val lineId = db.insertOrThrow("activity_lines", null, lineValues)

            db.setTransactionSuccessful()
            return lineId
        } finally {
            db.endTransaction()
        }
    }

    private fun parseQuickPresets(raw: String?): List<String> {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) {
            return DEFAULT_QUICK_PRESETS
        }
        return try {
            val jsonArray = JSONArray(trimmed)
            val result = mutableListOf<String>()
            for (i in 0 until jsonArray.length()) {
                val item = jsonArray.optString(i, "").trim()
                if (item.isNotEmpty()) {
                    result.add(item)
                }
            }
            result
        } catch (_: JSONException) {
            DEFAULT_QUICK_PRESETS
        }
    }
}
