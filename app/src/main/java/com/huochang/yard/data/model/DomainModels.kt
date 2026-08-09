package com.huochang.yard.data.model

import kotlinx.serialization.Serializable

/**
 * Domain models for the Yard Accounting app.
 *
 * These mirror the data that the original PWA stored in localStorage
 * (hc_types, hc_prices, hc_records, hc_profile, hc_salary, hc_cfg) but are
 * expressed as idiomatic Kotlin types. The persistence layer (Room) maps
 * these to/from entities.
 */

const val SHIFT_DAY = "day"
const val SHIFT_NIGHT = "night"

@Serializable
data class WorkType(
    val id: String,
    val name: String,
    val group: String,
    val color: String,   // hex string e.g. "#007AFF"
    val icon: String,
    val price: Double    // 元/车
)

@Serializable
data class YardRecord(
    val id: String,
    val date: String,        // yyyy-MM-dd
    val name: String,
    val car: String,
    val shift: String,       // SHIFT_DAY | SHIFT_NIGHT
    val counts: Map<String, Int>,
    val note: String,
    val upd: Long = System.currentTimeMillis()
)

@Serializable
data class Profile(
    val name: String,
    val car: String,
    val site: String
)

@Serializable
data class Salary(
    val base: Double,
    val meal: Double,
    val night: Double,
    val bonus: Double,
    val deduct: Double
)

@Serializable
data class AppConfig(
    val theme: String,   // "system" | "light" | "dark"
    val tint: String,    // hex accent color
    val hideAmt: Boolean,
    val dayGoal: Int,
    val moGoal: Int,
    val defName: String,
    val defCar: String,
    val lastShift: String
)

/** Full backup payload used by JSON export/import. */
@Serializable
data class BackupData(
    val types: List<WorkType>,
    val records: List<YardRecord>,
    val profile: Profile,
    val salary: Salary,
    val config: AppConfig
)

/** Default work types seeded on first launch (matches the PWA defaults). */
val DEFAULT_WORK_TYPES = listOf(
    WorkType("t_load", "货场装车", "load", "#007AFF", "truck", 2.00),
    WorkType("t_stack", "货场归剁", "stack", "#5856D6", "box", 1.50),
    WorkType("t_out", "外倒装车", "xfer", "#FF9500", "truck", 1.80),
    WorkType("t_in", "内倒装车", "xfer", "#FF3B30", "truck", 1.80),
    WorkType("t_instk", "内倒归剁", "stack", "#34C759", "box", 1.50)
)

val DEFAULT_CONFIG = AppConfig(
    theme = "system",
    tint = "#007AFF",
    hideAmt = false,
    dayGoal = 100,
    moGoal = 2500,
    defName = "",
    defCar = "",
    lastShift = SHIFT_DAY
)

val DEFAULT_PROFILE = Profile(name = "", car = "", site = "主货场")
val DEFAULT_SALARY = Salary(base = 0.0, meal = 0.0, night = 0.0, bonus = 0.0, deduct = 0.0)

/** Available accent (tint) colors shown in Settings, matching the PWA swatches. */
val TINT_OPTIONS = listOf(
    "#007AFF", "#5856D6", "#AF52DE", "#FF3B30",
    "#FF9500", "#34C759", "#FF6482", "#64D2FF"
)
