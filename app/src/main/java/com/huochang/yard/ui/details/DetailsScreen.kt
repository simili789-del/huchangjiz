package com.huochang.yard.ui.details

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import com.huochang.yard.ui.theme.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewModelScope
import com.huochang.yard.data.model.WorkType
import com.huochang.yard.data.model.YardRecord
import com.huochang.yard.ui.BaseYardViewModel
import com.huochang.yard.ui.components.*
import com.huochang.yard.util.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

class DetailsViewModel(application: Application) : BaseYardViewModel(application) {

    data class DetailsForm(
        val startDate: String = firstDayOfMonthStr(),
        val endDate: String = todayStr(),
        val keyword: String = "",
        val shift: String = "all",
        val quick: String = "month",
        val sort: String = "desc"
    )

    data class DayRow(val date: String, val desc: String, val cars: Int)

    data class DetailsUiState(
        val types: List<WorkType> = emptyList(),
        val hideAmt: Boolean = false,
        val last7: List<DayRow> = emptyList(),
        val filtered: List<YardRecord> = emptyList(),
        val totalCars: Int = 0,
        val totalAmt: Double = 0.0,
        val count: Int = 0
    )

    private val _form = MutableStateFlow(DetailsForm())
    val form: StateFlow<DetailsForm> = _form.asStateFlow()

    private val _selected = MutableStateFlow<Set<String>>(emptySet())
    val selectedIds: StateFlow<Set<String>> = _selected.asStateFlow()

    val uiState: StateFlow<DetailsUiState> = combine(_form, repo.workTypes, repo.records, repo.config) { f, types, records, config ->
        val matrix = last7Days().map { dStr ->
            val dayRecs = records.filter { it.date == dStr }
            val typeMap = mutableMapOf<String, Int>()
            var cars = 0
            dayRecs.forEach { r -> r.counts.forEach { (id, c) -> typeMap[id] = (typeMap[id] ?: 0) + c; cars += c } }
            val desc = typeMap.entries.joinToString("·") { (id, c) -> "${types.find { t -> t.id == id }?.name ?: ""}${c}车" }
            DayRow(dStr.substring(5), desc, cars)
        }

        val kw = f.keyword.lowercase()
        val prices = priceMap(types)
        val filtered = records.filter { r ->
            r.date >= f.startDate && r.date <= f.endDate &&
                    (f.shift == "all" || r.shift == f.shift) &&
                    (kw.isBlank() || r.name.lowercase().contains(kw) || r.car.lowercase().contains(kw))
        }.sortedWith(if (f.sort == "asc") compareBy { it.date } else compareByDescending { it.date })

        var totalCars = 0
        var totalAmt = 0.0
        filtered.forEach { r -> totalCars += recordCars(r.counts); totalAmt += recordMoney(r.counts, prices) }

        DetailsUiState(
            types = types, hideAmt = config.hideAmt, last7 = matrix,
            filtered = filtered, totalCars = totalCars, totalAmt = totalAmt, count = filtered.size
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), DetailsUiState())

    fun setStartDate(d: String) = _form.update { it.copy(startDate = d, quick = "") }
    fun setEndDate(d: String) = _form.update { it.copy(endDate = d, quick = "") }
    fun setKeyword(k: String) = _form.update { it.copy(keyword = k) }
    fun setShift(s: String) = _form.update { it.copy(shift = s) }
    fun setSort(s: String) = _form.update { it.copy(sort = s) }
    fun setQuickFilter(key: String) {
        val (start, end) = quickFilterRange(key)
        _form.update { it.copy(quick = key, startDate = start, endDate = end) }
    }

    fun toggleSelect(id: String) =
        _selected.update { if (it.contains(id)) it - id else it + id }

    fun clearSelection() = _selected.update { emptySet() }

    suspend fun deleteSelected(): Int {
        val ids = _selected.value
        repo.deleteRecords(ids)
        clearSelection()
        return ids.size
    }

    suspend fun deleteRecord(id: String) = repo.deleteRecord(id)

    suspend fun buildSelectedCsv(): String? = repo.buildSelectedCsv(_selected.value)
}

@Composable
fun DetailsScreen(viewModel: DetailsViewModel = viewModel()) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val form by viewModel.form.collectAsStateWithLifecycle()
    val ui by viewModel.uiState.collectAsStateWithLifecycle()
    val selected by viewModel.selectedIds.collectAsStateWithLifecycle()
    val prices = remember(ui.types) { priceMap(ui.types) }
    var pendingDelete by remember { mutableStateOf<YardRecord?>(null) }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        item { SectionTitle("近7天各类型车数") }
        item {
            GroupedCard {
                ui.last7.forEach { row ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(row.date, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(40.dp))
                        Text(row.desc.ifBlank { "—" }, modifier = Modifier.weight(1f).padding(horizontal = 8.dp), fontSize = 13.sp)
                        Text(if (row.cars > 0) "${row.cars}车" else "—", fontWeight = FontWeight.Bold)
                    }
                }
            }
        }

        item { SectionTitle("日期查询与筛选") }
        item {
            GroupedCard {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    DateField(form.startDate, viewModel::setStartDate)
                    Text("至", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                    DateField(form.endDate, viewModel::setEndDate)
                }
                Spacer(Modifier.height(10.dp))
                FilterChipRow(
                    listOf("today" to "今天", "7days" to "近7天", "month" to "本月", "lastmonth" to "上月"),
                    form.quick.ifBlank { "month" }, viewModel::setQuickFilter
                )
                Spacer(Modifier.height(10.dp))
                FilterChipRow(
                    listOf("all" to "全部班次", "day" to "☀️白班", "night" to "🌙夜班"),
                    form.shift, viewModel::setShift
                )
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = form.keyword, onValueChange = viewModel::setKeyword,
                        placeholder = { Text("搜索姓名/车号") }, singleLine = true,
                        leadingIcon = { Icon(Icons.Filled.Search, null) },
                        modifier = Modifier.weight(1f)
                    )
                    OutlinedButton(onClick = { viewModel.setSort(if (form.sort == "desc") "asc" else "desc") }) {
                        Text(if (form.sort == "desc") "日期↓" else "日期↑")
                    }
                }
            }
        }

        item { SectionTitle("车数明细汇总") }
        item {
            GroupedCard {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("${form.startDate} ~ ${form.endDate} (${ui.count}条)", fontWeight = FontWeight.Bold)
                    Text("合计: ${ui.totalCars}车 · " + formatMoney(ui.totalAmt, ui.hideAmt), fontWeight = FontWeight.Bold)
                }
            }
        }

        if (selected.isNotEmpty()) {
            item {
                Surface(
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(12.dp, 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("已选择 ${selected.size} 条", fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            TextButton(onClick = {
                                scope.launch {
                                    val csv = viewModel.buildSelectedCsv()
                                    if (csv != null) FileSharer.shareText(context, "货场记账_选中明细.csv", csv, "text/csv")
                                    else scope.toast("没有可导出的记录")
                                }
                            }) { Text("导出CSV") }
                            TextButton(onClick = {
                                scope.launch {
                                    val n = viewModel.deleteSelected()
                                    scope.toast("已删除 $n 条记录", "撤销") { viewModel.undoDelete() }
                                }
                            }, colors = ButtonDefaults.textButtonColors(contentColor = Red)) { Text("删除") }
                            TextButton(onClick = viewModel::clearSelection) { Text("取消") }
                        }
                    }
                }
            }
        }

        item { SectionTitle("记录列表") }
        if (ui.filtered.isEmpty()) {
            item { Text("没有符合条件的明细记录", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth().padding(38.dp), textAlign = TextAlign.Center) }
        } else {
            items(ui.filtered) { rec ->
                RecordCard(
                    record = rec, types = ui.types, prices = prices, hideAmt = ui.hideAmt,
                    onEdit = { },
                    onDelete = { pendingDelete = rec },
                    showCheck = true,
                    checked = selected.contains(rec.id),
                    onToggleCheck = { viewModel.toggleSelect(rec.id) },
                    showEdit = false
                )
                Spacer(Modifier.height(8.dp))
            }
        }
    }

    pendingDelete?.let { rec ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("确认删除") },
            text = { Text("确定要删除这条记录吗？此操作可撤销。") },
            confirmButton = {
                TextButton(onClick = {
                    scope.launch { viewModel.deleteRecord(rec.id) }
                    scope.toast("已删除记录", "撤销") { viewModel.undoDelete() }
                    pendingDelete = null
                }, colors = ButtonDefaults.textButtonColors(contentColor = Red)) { Text("确认删除") }
            },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text("取消") } }
        )
    }
}
