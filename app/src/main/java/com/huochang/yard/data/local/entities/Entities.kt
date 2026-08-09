package com.huochang.yard.data.local.entities

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.huochang.yard.data.model.*

/**
 * Room entities. `counts` on a record is stored as a compact string because
 * SQLite has no native map type (see [com.huochang.yard.data.local.Converters]).
 *
 * Profile / Salary / AppConfig are singletons stored with a fixed primary key.
 */

@Entity(tableName = "records")
data class RecordEntity(
    @PrimaryKey val id: String,
    val date: String,
    val name: String,
    val car: String,
    val shift: String,
    val countsJson: String,
    val note: String,
    val upd: Long
)

@Entity(tableName = "work_types")
data class WorkTypeEntity(
    @PrimaryKey val id: String,
    val name: String,
    val groupName: String,
    val color: String,
    val icon: String,
    val price: Double
)

@Entity(tableName = "profile")
data class ProfileEntity(
    @PrimaryKey val id: String = "singleton",
    val name: String,
    val car: String,
    val site: String
)

@Entity(tableName = "salary")
data class SalaryEntity(
    @PrimaryKey val id: String = "singleton",
    val base: Double,
    val meal: Double,
    val night: Double,
    val bonus: Double,
    val deduct: Double
)

@Entity(tableName = "app_config")
data class AppConfigEntity(
    @PrimaryKey val id: String = "singleton",
    val theme: String,
    val tint: String,
    val hideAmt: Boolean,
    val dayGoal: Int,
    val moGoal: Int,
    val defName: String,
    val defCar: String,
    val lastShift: String
)

// ---- Mapping helpers ----

fun WorkTypeEntity.toDomain() = WorkType(
    id = id, name = name, group = groupName, color = color, icon = icon, price = price
)

fun WorkType.toEntity() = WorkTypeEntity(
    id = id, name = name, groupName = group, color = color, icon = icon, price = price
)

fun ProfileEntity.toDomain() = Profile(name, car, site)
fun Profile.toEntity() = ProfileEntity(name = name, car = car, site = site)

fun SalaryEntity.toDomain() = Salary(base, meal, night, bonus, deduct)
fun Salary.toEntity() = SalaryEntity(base = base, meal = meal, night = night, bonus = bonus, deduct = deduct)

fun AppConfigEntity.toDomain() = AppConfig(theme, tint, hideAmt, dayGoal, moGoal, defName, defCar, lastShift)
fun AppConfig.toEntity() = AppConfigEntity(
    theme = theme, tint = tint, hideAmt = hideAmt, dayGoal = dayGoal, moGoal = moGoal,
    defName = defName, defCar = defCar, lastShift = lastShift
)
