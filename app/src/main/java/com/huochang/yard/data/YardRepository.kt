package com.huochang.yard.data

import com.huochang.yard.data.local.AppDatabase
import com.huochang.yard.data.local.Converters
import com.huochang.yard.data.local.toDomain
import com.huochang.yard.data.local.entities.*
import com.huochang.yard.data.model.*
import com.huochang.yard.util.recordCars
import com.huochang.yard.util.recordMoney
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.text.SimpleDateFormat
import java.util.*

/**
 * Single source of truth for the app.
 *
 * - [records] / [workTypes] are exposed as reactive Room flows.
 * - [config] / [profile] / [salary] are small singletons held in StateFlows
 *   (seeded from Room on first launch) so the UI re-composes on every change.
 *
 * This replaces the PWA's localStorage-backed `App` class.
 */
class YardRepository(private val db: AppDatabase) {

    // ---- Reactive streams (domain types) ----
    val records: Flow<List<YardRecord>> = db.recordDao().observeAll()
        .map { list -> list.map { it.toDomain(Converters.jsonToMap(it.countsJson)) } }
        .flowOn(Dispatchers.IO)

    val workTypes: Flow<List<WorkType>> = db.workTypeDao().observeAll()
        .map { list -> list.map { it.toDomain() } }
        .flowOn(Dispatchers.IO)

    private val _config = MutableStateFlow(DEFAULT_CONFIG)
    val config: StateFlow<AppConfig> = _config.asStateFlow()

    private val _profile = MutableStateFlow(DEFAULT_PROFILE)
    val profile: StateFlow<Profile> = _profile.asStateFlow()

    private val _salary = MutableStateFlow(DEFAULT_SALARY)
    val salary: StateFlow<Salary> = _salary.asStateFlow()

    private var lastDeleted: List<RecordEntity> = emptyList()

    /** Seed default data on first launch. Call from Application.onCreate(). */
    suspend fun initData() = withContext(Dispatchers.IO) {
        if (db.workTypeDao().count() == 0) {
            db.workTypeDao().upsertAll(DEFAULT_WORK_TYPES.map { it.toEntity() })
        }
        if (db.configDao().configCount() == 0) {
            db.configDao().upsertConfig(DEFAULT_CONFIG.toEntity())
        }
        db.configDao().getConfig()?.let { _config.value = it.toDomain() }
        db.configDao().getProfile()?.let { _profile.value = it.toDomain() }
        db.configDao().getSalary()?.let { _salary.value = it.toDomain() }
    }

    // ---- Record operations ----

    data class SaveRequest(
        val id: String? = null,
        val date: String,
        val name: String,
        val car: String,
        val shift: String,
        val counts: Map<String, Int>,
        val note: String
    )

    /**
     * Create or update a record. Mirrors the PWA "smart merge": when not
     * editing, a record with the same date + name + car + shift is found and
     * its counts are added to; otherwise a new record is created.
     */
    suspend fun saveRecord(req: SaveRequest) = withContext(Dispatchers.IO) {
        val totalCars = recordCars(req.counts)
        require(req.name.isNotBlank()) { "请输入姓名" }
        require(totalCars > 0) { "请至少录入一项车数" }

        if (req.id != null) {
            val existing = db.recordDao().getById(req.id)
            if (existing != null) {
                db.recordDao().update(
                    existing.copy(
                        date = req.date,
                        name = req.name,
                        car = req.car,
                        shift = req.shift,
                        countsJson = Converters.mapToJson(req.counts),
                        note = req.note,
                        upd = System.currentTimeMillis()
                    )
                )
                return@withContext
            }
        }

        val match = db.recordDao().findMatch(req.date, req.name, req.car, req.shift)
        if (match != null) {
            val merged = req.counts.mapValues { (k, v) ->
                Converters.jsonToMap(match.countsJson)[k]?.plus(v) ?: v
            }
            val mergedNote = if (req.note.isBlank()) match.note
            else if (match.note.isBlank()) req.note else "${match.note} ; ${req.note}"
            db.recordDao().update(
                match.copy(
                    countsJson = Converters.mapToJson(merged),
                    note = mergedNote,
                    upd = System.currentTimeMillis()
                )
            )
        } else {
            db.recordDao().insert(
                RecordEntity(
                    id = genId(),
                    date = req.date,
                    name = req.name,
                    car = req.car,
                    shift = req.shift,
                    countsJson = Converters.mapToJson(req.counts),
                    note = req.note,
                    upd = System.currentTimeMillis()
                )
            )
        }
    }

    suspend fun deleteRecord(id: String) = withContext(Dispatchers.IO) {
        val rec = db.recordDao().getById(id) ?: return@withContext
        lastDeleted = listOf(rec)
        db.recordDao().deleteById(id)
    }

    suspend fun deleteRecords(ids: Set<String>) = withContext(Dispatchers.IO) {
        val all = db.recordDao().getAll()
        lastDeleted = all.filter { it.id in ids }
        db.recordDao().deleteByIds(ids.toList())
    }

    fun canUndoDelete(): Boolean = lastDeleted.isNotEmpty()

    suspend fun undoDelete() = withContext(Dispatchers.IO) {
        if (lastDeleted.isNotEmpty()) {
            db.recordDao().insertAll(lastDeleted)
            lastDeleted = emptyList()
        }
    }

    /** Copy yesterday's records to today (optionally filtered by name). */
    suspend fun copyYesterday(target: String) = withContext(Dispatchers.IO) {
        val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        val cal = Calendar.getInstance()
        cal.add(Calendar.DATE, -1)
        val yestStr = fmt.format(cal.time)
        val todayStr = fmt.format(Date())

        val yest = db.recordDao().getByDate(yestStr)
            .filter { target == "all" || it.name == target }
        if (yest.isEmpty()) return@withContext

        val copies = yest.map { rec ->
            rec.copy(id = genId(), date = todayStr, upd = System.currentTimeMillis())
        }
        db.recordDao().insertAll(copies)
    }

    // ---- Work type operations ----

    suspend fun addWorkType(name: String, price: Double) = withContext(Dispatchers.IO) {
        require(name.isNotBlank()) { "请输入类型名称" }
        val colors = listOf("#007AFF", "#5856D6", "#FF9500", "#FF3B30", "#34C759", "#AF52DE")
        val color = colors.random()
        db.workTypeDao().upsert(
            WorkTypeEntity(
                id = "t_" + System.currentTimeMillis().toString(36),
                name = name,
                groupName = "load",
                color = color,
                icon = "box",
                price = price
            )
        )
    }

    suspend fun updatePrice(id: String, price: Double) = withContext(Dispatchers.IO) {
        val all = db.workTypeDao().getAll()
        all.find { it.id == id }?.let {
            db.workTypeDao().upsert(it.copy(price = price))
        }
    }

    suspend fun deleteWorkType(id: String) = withContext(Dispatchers.IO) {
        db.workTypeDao().deleteById(id)
        // Strip this type's counts out of every record.
        val all = db.recordDao().getAll()
        all.forEach { rec ->
            val map = Converters.jsonToMap(rec.countsJson).toMutableMap()
            if (map.remove(id) != null) {
                db.recordDao().update(rec.copy(countsJson = Converters.mapToJson(map)))
            }
        }
    }

    // ---- Singleton config ----

    suspend fun saveProfile(p: Profile) = withContext(Dispatchers.IO) {
        db.configDao().upsertProfile(p.toEntity())
        _profile.value = p
    }

    suspend fun saveSalary(s: Salary) = withContext(Dispatchers.IO) {
        db.configDao().upsertSalary(s.toEntity())
        _salary.value = s
    }

    suspend fun saveConfig(c: AppConfig) = withContext(Dispatchers.IO) {
        db.configDao().upsertConfig(c.toEntity())
        _config.value = c
    }

    // ---- Data management ----

    suspend fun loadSampleData() = withContext(Dispatchers.IO) {
        val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        val today = fmt.format(Date())
        val cal = Calendar.getInstance().apply { add(Calendar.DATE, -1) }
        val yest = fmt.format(cal.time)
        val now = System.currentTimeMillis()

        db.recordDao().insertAll(
            listOf(
                RecordEntity(genId(), today, "李四明", "港30", SHIFT_DAY,
                    Converters.mapToJson(mapOf("t_load" to 25, "t_out" to 10)),
                    "白班作业顺畅", now),
                RecordEntity(genId(), today, "胡晓银", "港28", SHIFT_NIGHT,
                    Converters.mapToJson(mapOf("t_stack" to 15, "t_instk" to 20)),
                    "夜班归剁", now),
                RecordEntity(genId(), yest, "李四明", "港30", SHIFT_DAY,
                    Converters.mapToJson(mapOf("t_load" to 30, "t_stack" to 10)),
                    "", now - 86400000),
                RecordEntity(genId(), yest, "胡晓银", "港28", SHIFT_DAY,
                    Converters.mapToJson(mapOf("t_out" to 20, "t_in" to 15)),
                    "", now - 86400000)
            )
        )
    }

    suspend fun clearAll() = withContext(Dispatchers.IO) {
        db.recordDao().clear()
        lastDeleted = emptyList()
    }

    // ---- Export / Import ----

    private suspend fun allRecordsDomain(): List<YardRecord> =
        db.recordDao().getAll().map { it.toDomain(Converters.jsonToMap(it.countsJson)) }

    private suspend fun allTypesDomain(): List<WorkType> =
        db.workTypeDao().getAll().map { it.toDomain() }

    /** Build a CSV for a given month (YYYY-MM). Returns null content if empty. */
    suspend fun buildMonthCsv(month: String): String? = withContext(Dispatchers.IO) {
        val types = allTypesDomain()
        val recs = allRecordsDomain().filter { it.date.startsWith(month) }
        if (recs.isEmpty()) return@withContext null
        csvFromRecords(types, recs, "货场记账_月报_$month.csv")
    }

    suspend fun buildSalaryCsv(month: String): String? = withContext(Dispatchers.IO) {
        val recs = allRecordsDomain().filter { it.date.startsWith(month) }
        val salary = _salary.value
        val personMap = mutableMapOf<String, Double>()
        recs.forEach { r ->
            personMap[r.name] = personMap.getOrDefault(r.name, 0.0) + recordMoney(r.counts, priceMap(allTypesDomain()))
        }
        if (personMap.isEmpty()) return@withContext null

        val headers = listOf("姓名", "计件", "底薪", "餐补", "加班", "工龄奖", "扣款", "应发工资")
        val lines = personMap.map { (name, piece) ->
            val total = piece + salary.base + salary.meal + salary.night + salary.bonus - salary.deduct
            listOf(q(name), f(piece), f(salary.base), f(salary.meal), f(salary.night), f(salary.bonus), f(salary.deduct), f(total)).joinToString(",")
        }
        "\uFEFF" + (listOf(headers.joinToString(",")) + lines).joinToString("\n")
    }

    suspend fun buildSelectedCsv(ids: Set<String>): String? = withContext(Dispatchers.IO) {
        val types = allTypesDomain()
        val recs = allRecordsDomain().filter { it.id in ids }
        if (recs.isEmpty()) return@withContext null
        csvFromRecords(types, recs, "货场记账_选中明细.csv")
    }

    private fun csvFromRecords(types: List<WorkType>, recs: List<YardRecord>, fileName: String): String {
        val headers = listOf("日期", "班次", "姓名", "车号") +
                types.map { it.name } + listOf("总车数", "金额", "备注")
        val lines = recs.map { r ->
            val row = mutableListOf<String>()
            row += r.date
            row += if (r.shift == SHIFT_NIGHT) "夜班" else "白班"
            row += q(r.name)
            row += q(r.car)
            types.forEach { t -> row += (r.counts[t.id] ?: 0).toString() }
            row += recordCars(r.counts).toString()
            row += "%.2f".format(recordMoney(r.counts, priceMap(types)))
            row += q(r.note)
            row.joinToString(",")
        }
        return "\uFEFF" + (listOf(headers.joinToString(",")) + lines).joinToString("\n")
    }

    suspend fun buildJsonBackup(): String = withContext(Dispatchers.IO) {
        val data = BackupData(
            types = allTypesDomain(),
            records = allRecordsDomain(),
            profile = _profile.value,
            salary = _salary.value,
            config = _config.value
        )
        Json.encodeToString(BackupData.serializer(), data)
    }

    suspend fun importJson(json: String) = withContext(Dispatchers.IO) {
        val data = Json { ignoreUnknownKeys = true }.decodeFromString(BackupData.serializer(), json)
        db.workTypeDao().upsertAll(data.types.map { it.toEntity() })
        db.recordDao().insertAll(data.records.map {
            RecordEntity(it.id, it.date, it.name, it.car, it.shift, Converters.mapToJson(it.counts), it.note, it.upd)
        })
        db.configDao().upsertProfile(data.profile.toEntity())
        db.configDao().upsertSalary(data.salary.toEntity())
        db.configDao().upsertConfig(data.config.toEntity())
        _profile.value = data.profile
        _salary.value = data.salary
        _config.value = data.config
    }

    /** Import records from a CSV produced by this app. Returns number added. */
    suspend fun importCsv(text: String): Int = withContext(Dispatchers.IO) {
        val lines = text.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.size < 2) return@withContext 0
        val types = allTypesDomain()
        val headers = lines[0].split(",").map { it.replace("\"", "").trim() }
        val dateIdx = headers.indexOfFirst { it.contains("日期") }
        val nameIdx = headers.indexOfFirst { it.contains("姓名") }
        val carIdx = headers.indexOfFirst { it.contains("车号") }
        val shiftIdx = headers.indexOfFirst { it.contains("班次") }
        val noteIdx = headers.indexOfFirst { it.contains("备注") }
        if (dateIdx < 0 || nameIdx < 0) return@withContext 0

        var added = 0
        val inserted = mutableListOf<RecordEntity>()
        for (i in 1 until lines.size) {
            val cols = lines[i].split(",").map { it.replace("\"", "").trim() }
            if (cols.getOrNull(dateIdx).isNullOrBlank()) continue
            val counts = mutableMapOf<String, Int>()
            types.forEach { t ->
                val idx = headers.indexOf(t.name)
                if (idx >= 0) counts[t.id] = cols.getOrNull(idx)?.toIntOrNull() ?: 0
            }
            val shift = if (shiftIdx >= 0 && (cols.getOrNull(shiftIdx) ?: "").contains("夜")) SHIFT_NIGHT else SHIFT_DAY
            inserted.add(
                RecordEntity(
                    id = genId(),
                    date = cols[dateIdx],
                    name = cols.getOrNull(nameIdx) ?: "未知",
                    car = if (carIdx >= 0) cols.getOrNull(carIdx) ?: "" else "",
                    shift = shift,
                    countsJson = Converters.mapToJson(counts),
                    note = if (noteIdx >= 0) cols.getOrNull(noteIdx) ?: "" else "",
                    upd = System.currentTimeMillis()
                )
            )
            added++
        }
        if (inserted.isNotEmpty()) db.recordDao().insertAll(inserted)
        added
    }

    private fun genId(): String =
        "R" + System.currentTimeMillis().toString(36) + UUID.randomUUID().toString(36).substring(2, 6)

    private fun q(s: String) = "\"$s\""
    private fun f(d: Double) = "%.2f".format(d)
}
