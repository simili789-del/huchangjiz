package com.huochang.yard.ui.report

import android.app.Application
import android.app.DatePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import com.huochang.yard.ui.theme.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewModelScope
import com.huochang.yard.data.model.SHIFT_NIGHT
import com.huochang.yard.data.model.WorkType
import com.huochang.yard.data.model.YardRecord
import com.huochang.yard.ui.BaseYardViewModel
import com.huochang.yard.ui.components.*
import com.huochang.yard.util.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.util.Calendar

data class PriceGroup(val price: Double, var count: Int, var dayCount: Int, var nightCount: Int, val types: MutableSet<String>)
data class TypeDist(val type: WorkType, var count: Int, var amount: Double)
data class PersonStat(var count: Int, var amount: Double, var dayCount: Int, var nightCount: Int)

class ReportViewModel(application: Application) : BaseYardViewModel(application) {

    data class ReportForm(val month: String = currentMonthStr(), val person: String = "all")

    data class ReportUiState(
        val types: List<WorkType> = emptyList(),
        val hideAmt: Boolean = false,
        val persons: List<String> = emptyList(),
        val priceGroups: List<PriceGroup> = emptyList(),
        val typeDist: List<TypeDist> = emptyList(),
        val personStats: List<Pair<String, PersonStat>> = emptyList(),
        val pieceIncome: Double = 0.0,
        val estSalary: Double = 0.0,
        val dailyCounts: List<Int> = emptyList()
    )

    private val _form = MutableStateFlow(ReportForm())
    val form: StateFlow<ReportForm> = _form.asStateFlow()

    val uiState: StateFlow<ReportUiState> = combine(_form, repo.workTypes, repo.records, repo.salary, repo.config) { f, types, records, salary, config ->
        val prices = priceMap(types)
        val monthRecs = records.filter { it.date.startsWith(f.month) && (f.person == "all" || it.name == f.person) }

        val priceGroups = mutableMapOf<Double, PriceGroup>()
        val typeDist = LinkedHashMap<String, TypeDist>()
        val personMap = mutableMapOf<String, PersonStat>()
        var pieceIncome = 0.0

        monthRecs.forEach { r ->
            types.forEach { t ->
                val c = r.counts[t.id] ?: 0
                if (c > 0) {
                    val p = t.price
                    val pg = priceGroups.getOrPut(p) { PriceGroup(p, 0, 0, 0, mutableSetOf()) }
                    pg.count += c
                    if (r.shift == SHIFT_NIGHT) pg.nightCount += c else pg.dayCount += c
                    pg.types.add(t.name)

                    val td = typeDist.getOrPut(t.id) { TypeDist(t, 0, 0.0) }
                    td.count += c
                    td.amount += c * p

                    val ps = personMap.getOrPut(r.name) { PersonStat(0, 0.0, 0, 0) }
                    ps.count += c
                    ps.amount += c * p
                    if (r.shift == SHIFT_NIGHT) ps.nightCount += c else ps.dayCount += c

                    pieceIncome += c * p
                }
            }
        }

        val estSalary = pieceIncome + salary.base + salary.meal + salary.night + salary.bonus - salary.deduct

        val (y, m) = f.month.split("-").let { it[0].toInt() to it[1].toInt() }
        val dim = daysInMonth(y, m)
        val daily = IntArray(dim) { 0 }
        monthRecs.forEach { r ->
            val d = r.date.substring(8, 10).toIntOrNull() ?: return@forEach
            if (d in 1..dim) daily[d - 1] += recordCars(r.counts)
        }

        val persons = records.map { it.name }.distinct()

        ReportUiState(
            types = types, hideAmt = config.hideAmt, persons = persons,
            priceGroups = priceGroups.values.toList(),
            typeDist = typeDist.values.toList(),
            personStats = personMap.toList(),
            pieceIncome = pieceIncome, estSalary = estSalary, dailyCounts = daily.toList()
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ReportUiState())

    fun setMonth(m: String) = _form.update { it.copy(month = m) }
    fun setPerson(p: String) = _form.update { it.copy(person = p) }

    suspend fun exportMonthCsv(): String? = repo.buildMonthCsv(form.value.month)
    suspend fun exportSalaryCsv(): String? = repo.buildSalaryCsv(form.value.month)
}

@Composable
fun ReportScreen(viewModel: ReportViewModel = viewModel()) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val form by viewModel.form.collectAsStateWithLifecycle()
    val ui by viewModel.uiState.collectAsStateWithLifecycle()
    val primary = MaterialTheme.colorScheme.primary

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        item { SectionTitle("月度选择") }
        item {
            GroupedCard {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    MonthField(form.month, viewModel::setMonth, modifier = Modifier.weight(1f))
                    PersonDropdown(form.person, ui.persons, viewModel::setPerson, modifier = Modifier.weight(1f))
                }
            }
        }

        item { SectionTitle("摘要核算（按单价）") }
        item {
            GroupedCard {
                if (ui.priceGroups.isEmpty()) {
                    Text("本月暂无记账数据", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(16.dp))
                } else {
                    ui.priceGroups.forEach { g ->
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("单价 " + formatMoney(g.price, ui.hideAmt) + " · ${g.count}车")
                            Text("☀️白${g.dayCount} · 🌙夜${g.nightCount}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }

        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SummaryCard(
                    modifier = Modifier.weight(1f), label = "月度计件收入",
                    value = formatMoney(ui.pieceIncome, ui.hideAmt), valueColor = Green
                )
                SummaryCard(
                    modifier = Modifier.weight(1f), label = "预估总工资",
                    value = formatMoney(ui.estSalary, ui.hideAmt), valueColor = primary
                )
            }
        }

        item { SectionTitle("每日车数柱状图") }
        item {
            GroupedCard {
                val max = (ui.dailyCounts.maxOrNull() ?: 0).coerceAtLeast(1)
                Row(
                    modifier = Modifier.fillMaxWidth().height(140.dp).padding(horizontal = 8.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.Bottom
                ) {
                    ui.dailyCounts.forEachIndexed { idx, c ->
                        val ratio = if (c > 0) (c.toFloat() / max).coerceAtLeast(0.04f) else 0.02f
                        Column(
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Bottom
                        ) {
                            Box(
                                modifier = Modifier.fillMaxWidth().fillMaxHeight(ratio)
                                    .clip(RoundedCornerShape(topStart = 5.dp, topEnd = 5.dp))
                                    .background(primary)
                            )
                            Text("${idx + 1}", fontSize = 9.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 4.dp))
                        }
                    }
                }
            }
        }

        item { SectionTitle("按单价分类汇总") }
        item {
            GroupedCard {
                ui.priceGroups.forEach { g ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column {
                            Text(formatMoney(g.price, ui.hideAmt), fontWeight = FontWeight.Bold)
                            Text(g.types.joinToString("、"), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text("${g.count}车 · " + formatMoney(g.count * g.price, ui.hideAmt), fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }

        item { SectionTitle("作业类型分布") }
        item {
            GroupedCard {
                ui.typeDist.forEach { td ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            TypeDot(td.type.color); Spacer(Modifier.width(6.dp)); Text(td.type.name)
                        }
                        Text("${td.count}车 · " + formatMoney(td.amount, ui.hideAmt), fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }

        item { SectionTitle("按人员统计") }
        item {
            GroupedCard {
                ui.personStats.forEach { (name, ps) ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column {
                            Text(name, fontWeight = FontWeight.Bold)
                            Text("白${ps.dayCount}·夜${ps.nightCount}", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text("${ps.count}车 · " + formatMoney(ps.amount, ui.hideAmt), fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }

        item {
            Button(
                onClick = { scope.launch { vmexport(context, viewModel::exportMonthCsv, "货场记账_月报_${form.month}.csv", scope) } },
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp).height(52.dp), shape = RoundedCornerShape(14.dp)
            ) { Text("导出本月 CSV") }
        }
        item {
            OutlinedButton(
                onClick = { scope.launch { vmexport(context, viewModel::exportSalaryCsv, "货场工资单_${form.month}.csv", scope) } },
                modifier = Modifier.fillMaxWidth().height(52.dp), shape = RoundedCornerShape(14.dp)
            ) { Text("导出工资单 CSV") }
        }
        item { Spacer(Modifier.height(8.dp)) }
    }
}

private suspend fun vmexport(
    context: android.content.Context,
    producer: suspend () -> String?,
    fileName: String,
    scope: kotlinx.coroutines.CoroutineScope
) {
    val csv = producer()
    if (csv != null) FileSharer.shareText(context, fileName, csv, "text/csv")
    else scope.toast("本月暂无记录可导出")
}

@Composable
private fun MonthField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val cal = Calendar.getInstance()
    value.split("-").let { if (it.size == 2) cal.set(it[0].toInt(), it[1].toInt() - 1, 1) }
    val dialog = DatePickerDialog(
        context,
        { _, y, m, _ -> onValueChange("%04d-%02d".format(y, m + 1)) },
        cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), 1
    )
    OutlinedTextField(
        value = value, onValueChange = {}, readOnly = true, singleLine = true,
        label = { Text("月份") },
        trailingIcon = { Icon(Icons.Filled.DateRange, null) },
        modifier = modifier.clickable { dialog.show() }
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PersonDropdown(value: String, persons: List<String>, onValueChange: (String) -> Unit, modifier: Modifier = Modifier) {
    var expanded by remember { mutableStateOf(false) }
    val options = listOf("全部") + persons
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = !expanded }, modifier = modifier) {
        OutlinedTextField(
            value = if (value == "all") "全部" else value,
            onValueChange = {}, readOnly = true, singleLine = true,
            label = { Text("人员") },
            trailingIcon = { Icon(Icons.Filled.ArrowDropDown, null) },
            modifier = Modifier.menuAnchor().fillMaxWidth()
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { opt ->
                val key = if (opt == "全部") "all" else opt
                DropdownMenuItem(text = { Text(opt) }, onClick = { onValueChange(key); expanded = false })
            }
        }
    }
}
