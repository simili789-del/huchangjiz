package com.huochang.yard.data.local

import androidx.room.*
import com.huochang.yard.data.local.entities.*
import kotlinx.coroutines.flow.Flow

@Dao
interface RecordDao {
    @Query("SELECT * FROM records ORDER BY upd DESC")
    fun observeAll(): Flow<List<RecordEntity>>

    @Query("SELECT * FROM records WHERE id = :id")
    suspend fun getById(id: String): RecordEntity?

    @Query("SELECT * FROM records WHERE date = :date AND name = :name AND car = :car AND shift = :shift LIMIT 1")
    suspend fun findMatch(date: String, name: String, car: String, shift: String): RecordEntity?

    @Query("SELECT * FROM records WHERE date = :date")
    suspend fun getByDate(date: String): List<RecordEntity>

    @Query("SELECT * FROM records")
    suspend fun getAll(): List<RecordEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(record: RecordEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(records: List<RecordEntity>)

    @Update
    suspend fun update(record: RecordEntity)

    @Query("DELETE FROM records WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM records WHERE id IN (:ids)")
    suspend fun deleteByIds(ids: List<String>)

    @Query("DELETE FROM records")
    suspend fun clear()
}

@Dao
interface WorkTypeDao {
    @Query("SELECT * FROM work_types")
    fun observeAll(): Flow<List<WorkTypeEntity>>

    @Query("SELECT * FROM work_types")
    suspend fun getAll(): List<WorkTypeEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(type: WorkTypeEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(types: List<WorkTypeEntity>)

    @Query("DELETE FROM work_types WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("SELECT COUNT(*) FROM work_types")
    suspend fun count(): Int
}

@Dao
interface ConfigDao {
    @Query("SELECT * FROM profile WHERE id = 'singleton'")
    suspend fun getProfile(): ProfileEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertProfile(p: ProfileEntity)

    @Query("SELECT * FROM salary WHERE id = 'singleton'")
    suspend fun getSalary(): SalaryEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSalary(s: SalaryEntity)

    @Query("SELECT * FROM app_config WHERE id = 'singleton'")
    suspend fun getConfig(): AppConfigEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertConfig(c: AppConfigEntity)

    @Query("SELECT COUNT(*) FROM app_config")
    suspend fun configCount(): Int
}
