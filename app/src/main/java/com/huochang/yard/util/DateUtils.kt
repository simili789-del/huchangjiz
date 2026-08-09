package com.huochang.yard.util

import java.text.SimpleDateFormat
import java.util.*

private val ymdFormat = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
private val weekNames = arrayOf("星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六")

fun formatDateStr(date: Date): String = ymdFormat.format(date)

fun todayStr(): String = ymdFormat.format(Date())

fun yesterdayStr(): String {
    val c = Calendar.getInstance().apply { add(Calendar.DATE, -1) }
    return ymdFormat.format(c.time)
}

/** Human friendly header like "2026年8月7日 星期五". */
fun headerDateString(): String {
    val c = Calendar.getInstance()
    return "${c.get(Calendar.YEAR)}年${c.get(Calendar.MONTH) + 1}月${c.get(Calendar.DATE)}日 ${weekNames[c.get(Calendar.DAY_OF_WEEK) - 1]}"
}

fun currentMonthStr(): String {
    val c = Calendar.getInstance()
    return "${c.get(Calendar.YEAR)}-${String.format("%02d", c.get(Calendar.MONTH) + 1)}"
}

fun firstDayOfMonthStr(): String {
    val c = Calendar.getInstance().apply { set(Calendar.DAY_OF_MONTH, 1) }
    return ymdFormat.format(c.time)
}

fun daysInMonth(year: Int, month: Int): Int {
    val c = Calendar.getInstance().apply { set(year, month - 1, 1) }
    return c.getActualMaximum(Calendar.DAY_OF_MONTH)
}

/** List of the last 7 dates (oldest first), as yyyy-MM-dd strings. */
fun last7Days(): List<String> {
    val out = mutableListOf<String>()
    val c = Calendar.getInstance()
    for (i in 6 downTo 0) {
        c.time = Date()
        c.add(Calendar.DATE, -i)
        out.add(ymdFormat.format(c.time))
    }
    return out
}

fun quickFilterRange(type: String): Pair<String, String> {
    val end = todayStr()
    val c = Calendar.getInstance()
    when (type) {
        "today" -> return end to end
        "7days" -> {
            c.add(Calendar.DATE, -6)
            return ymdFormat.format(c.time) to end
        }
        "month" -> return firstDayOfMonthStr() to end
        "lastmonth" -> {
            val start = Calendar.getInstance().apply {
                add(Calendar.MONTH, -1)
                set(Calendar.DAY_OF_MONTH, 1)
            }
            val e = Calendar.getInstance().apply { set(Calendar.DAY_OF_MONTH, 1); add(Calendar.DATE, -1) }
            return ymdFormat.format(start.time) to ymdFormat.format(e.time)
        }
    }
    return end to end
}
