package com.huochang.yard.util

import com.huochang.yard.data.model.YardRecord

/** Pure calculation helpers shared by the repository and the UI layer. */

fun recordCars(counts: Map<String, Int>): Int =
    counts.values.fold(0) { acc, v -> acc + v }

fun recordMoney(counts: Map<String, Int>, prices: Map<String, Double>): Double =
    counts.entries.fold(0.0) { acc, (id, count) -> acc + count * (prices[id] ?: 0.0) }

/** Build a quick lookup map typeId -> price from a list of work types. */
fun priceMap(types: List<com.huochang.yard.data.model.WorkType>): Map<String, Double> =
    types.associate { it.id to it.price }

fun totalCars(records: List<YardRecord>): Int =
    records.fold(0) { acc, r -> acc + recordCars(r.counts) }

fun totalMoney(records: List<YardRecord>, prices: Map<String, Double>): Double =
    records.fold(0.0) { acc, r -> acc + recordMoney(r.counts, prices) }
