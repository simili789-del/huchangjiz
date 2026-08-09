package com.huochang.yard.data.local

import androidx.room.TypeConverter
import com.huochang.yard.data.local.entities.RecordEntity

/**
 * Room type converters. The per-record counts map (typeId -> car count) is
 * serialized to a compact "k1=v1,k2=v2" string. We avoid a JSON dependency by
 * using this trivial, robust format.
 */
object Converters {

    @TypeConverter
    fun fromCountsMap(map: Map<String, Int>): String =
        map.entries.joinToString(",") { "${it.key}=${it.value}" }

    @TypeConverter
    fun toCountsMap(raw: String?): Map<String, Int> {
        if (raw.isNullOrEmpty()) return emptyMap()
        return raw.split(",").mapNotNull { pair ->
            val idx = pair.indexOf('=')
            if (idx <= 0) return@mapNotNull null
            val key = pair.substring(0, idx)
            val value = pair.substring(idx + 1).toIntOrNull() ?: 0
            key to value
        }.toMap()
    }

    // Convenience used by the repository when building domain records.
    fun mapToJson(map: Map<String, Int>): String = fromCountsMap(map)
    fun jsonToMap(raw: String?): Map<String, Int> = toCountsMap(raw)
}

fun RecordEntity.toDomain(counts: Map<String, Int>) = com.huochang.yard.data.model.YardRecord(
    id = id, date = date, name = name, car = car, shift = shift,
    counts = counts, note = note, upd = upd
)
