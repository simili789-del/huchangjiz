package com.huochang.yard.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.huochang.yard.data.local.entities.*

@Database(
    entities = [
        RecordEntity::class,
        WorkTypeEntity::class,
        ProfileEntity::class,
        SalaryEntity::class,
        AppConfigEntity::class
    ],
    version = 1,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun recordDao(): RecordDao
    abstract fun workTypeDao(): WorkTypeDao
    abstract fun configDao(): ConfigDao

    companion object {
        const val DATABASE_NAME = "yard_accounting.db"
    }
}
