package com.huochang.yard.ui.today

import android.app.Application
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pointerInput
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.awaitPointerEventScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import com.huochang.yard.ui.theme.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.huochang.yard.data.model.SHIFT_DAY
import com.huochang.yard.data.model.SHIFT_NIGHT
import com.huochang.yard.data.model.WorkType
import com.huochang.yard.data.model.YardRecord
import com.huochang.yard.data.YardRepository
import com.huochang.yard.ui.BaseYardViewModel
import com.huochang.yard.ui.components.*
import com.huochang.yard.ui.theme.Green
import com.huochang.yard.util.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlinx.coroutines.delay

class TodayViewModel(application: Application) : BaseYardViewModel(application) {

    data class TodayForm(
        val date: String = todayStr(),
        val name: String = "",
        val car: String = "",
        val shift: String = SHIFT_DAY,
        val counts: Map<String, Int> = emptyMap(),
        val note: String = "",
        val editingId: String? = null
    )

    data class TodayUiState(
        val types: List<WorkType> = emptyList(),
        val hideAmt: Boolean = false,
        val dayGoal: Int = 100,
        val liveTotal: Double = 0.0,
        val todayCars: Int = 0,
        val todayDayCars: Int = 0,
        val todayNightCars: Int = 0,
        val todayIncome: Double = 0.0,
        val yestCars: Int = 0,
        val yestIncome: Double = 0.0,
        val yestTypeCounts: Map<String, Int> = emptyMap(),
        val yestNames: List<String> = emptyList(),
        val todayRecords: List<YardRecord> = emptyList()
    )

    private val _form = MutableStateFlow(
        TodayForm(
            date = todayStr(),
            name = repo.profile.value.name.ifBlank { repo.config.value.defName },
            car = repo.profile.value.car.ifBlank { repo.config.value.defCar },
            shift = repo.config.value.lastShift
        )
    )
    val form: StateFlow<TodayForm> = _form.asStateFlow()

    val uiState: StateFlow<TodayUiState> = combine(_form, repo.workTypes, repo.records, repo.config) { f, types, records, config ->
        val prices = priceMap(types)
        val liveTotal = recordMoney(f.counts, prices)
        val today = todayStr()
        val todayRecs = records.filter { it.date == today }
        var dayCars = 0
        var nightCars = 0
        todayRecs.forEach { if (it.shift == SHIFT_NIGHT) nightCars += recordCars(it.counts) else dayCars += recordCars(it.counts) }
        val todayIncome = totalMoney(todayRecs, prices)

        val yest = yesterdayStr()
        val yestRecs = records.filter { it.date == yest }
        var yestCars = 0
        var yestIncome = 0.0
        val yestTypeCounts = mutableMapOf<String, Int>()
        yestRecs.forEach { r ->
            yestCars += recordCars(r.counts)
            yestIncome += recordMoney(r.counts, prices)
            r.counts.forEach { (id, c) -> yestTypeCounts[id] = (yestTypeCounts[id] ?: 0) + c }
        }
        val yestNames = yestRecs.map { it.name }.distinct()

        TodayUiState(
            types = types, hideAmt = config.hideAmt, dayGoal = config.dayGoal,
            liveTotal = liveTotal, todayCars = totalCars(todayRecs), todayDayCars = dayCars,
            todayNightCars = nightCars, todayIncome = todayIncome,
            yestCars = yestCars, yestIncome = yestIncome, yestTypeCounts = yestTypeCounts,
            yestNames = yestNames, todayRecords = todayRecs
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), TodayUiState())

    fun setDate(d: String) = _form.update { it.copy(date = d) }
    fun setName(n: String) = _form.update { it.copy(name = n) }
    fun setCar(c: String) = _form.update { it.copy(car = c) }
    fun setShift(s: String) = _form.update { it.copy(shift = s) }
    fun setNote(n: String) = _form.update { it.copy(note = n) }
    fun setCount(typeId: String, value: Int) =
        _form.update { it.copy(counts = it.counts.toMutableMap().apply { put(typeId, maxOf(0, value)) }) }
    fun stepCount(typeId: String, delta: Int) =
        setCount(typeId, (_form.value.counts[typeId] ?: 0) + delta)

    fun resetForm() = _form.update { it.copy(counts = emptyMap(), note = "", editingId = null) }

    sealed interface SaveResult {
        data object Success : SaveResult
        data class Error(val msg: String) : SaveResult
    }

    suspend fun save(): SaveResult {
        val f = _form.value
        if (f.name.isBlank()) return SaveResult.Error("请输入姓名")
        if (recordCars(f.counts) == 0) return SaveResult.Error("请至少录入一项车数")
        return runCatching {
            repo.saveRecord(
                YardRepository.SaveRequest(
                    id = f.editingId, date = f.date, name = f.name, car = f.car,
                    shift = f.shift, counts = f.counts, note = f.note
                )
            )
            resetForm()
        }.fold(
            onSuccess = { SaveResult.Success },
            onFailure = { SaveResult.Error(it.message ?: "保存失败") }
        )
    }

    fun editRecord(id: String) {
        viewModelScope.launch {
            val rec = repo.records.first().find { it.id == id } ?: return@launch
            _form.value = _form.value.copy(
                date = rec.date, name = rec.name, car = rec.car, shift = rec.shift,
                counts = rec.counts, note = rec.note, editingId = id
            )
        }
    }

    fun cancelEdit() = resetForm()

    suspend fun deleteRecord(id: String) {
        runCatching { repo.deleteRecord(id) }
    }

    suspend fun copyYesterday(target: String) {
        runCatching { repo.copyYesterday(target) }
    }
}

@Composable
fun TodayScreen(viewModel: TodayViewModel = viewModel()) {
    val scope = rememberCoroutineScope()
    val form by viewModel.form.collectAsStateWithLifecycle()
    val ui by viewModel.uiState.collectAsStateWithLifecycle()
    val prices = remember(ui.types) { priceMap(ui.types) }
    var pendingDelete by remember { mutableStateOf<YardRecord?>(null) }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        item { SectionTitle("快速记账") }
        item {
            GroupedCard {
                FormRow("日期") { DateField(form.date, viewModel::setDate) }
                FormRow("姓名") {
                    OutlinedTextField(
                        value = form.name, onValueChange = viewModel::setName,
                        placeholder = { Text("请输入姓名") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                FormRow("车号") {
                    OutlinedTextField(
                        value = form.car, onValueChange = viewModel::setCar,
                        placeholder = { Text("请输入车号") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                FormRow("班次") { ShiftSelector(form.shift, viewModel::setShift) }
                ui.types.forEach { type ->
                    StepperRow(
                        type = type,
                        count = form.counts[type.id] ?: 0,
                        hideAmt = ui.hideAmt,
                        onStep = { delta -> viewModel.stepCount(type.id, delta) },
                        onSet = { value -> viewModel.setCount(type.id, value) }
                    )
                }
                FormRow("备注") {
                    OutlinedTextField(
                        value = form.note, onValueChange = viewModel::setNote,
                        placeholder = { Text("选填") }, singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        }

        if (form.editingId != null) {
            item {
                Surface(
                    color = Orange.copy(alpha = 0.12f),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("正在编辑记录", color = Orange, fontWeight = FontWeight.Bold)
                        TextButton(onClick = viewModel::cancelEdit, colors = ButtonDefaults.textButtonColors(contentColor = Red)) {
                            Text("取消编辑")
                        }
                    }
                }
            }
        }

        item {
            Button(
                onClick = {
                    scope.launch {
                        when (val r = viewModel.save()) {
                            TodayViewModel.SaveResult.Success -> scope.toast("记录成功")
                            is TodayViewModel.SaveResult.Error -> scope.toast(r.msg)
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth().padding(top = 14.dp).height(52.dp),
                shape = RoundedCornerShape(14.dp)
            ) {
                Icon(Icons.Filled.Check, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("保存 · " + formatMoney(ui.liveTotal, ui.hideAmt))
            }
        }

        item { SectionTitle("今日摘要") }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SummaryCard(
                    modifier = Modifier.weight(1f),
                    label = "今日车数",
                    value = formatCount(ui.todayCars, ui.hideAmt),
                    footer = {
                        Text("☀️白 ${ui.todayDayCars} · 🌙夜 ${ui.todayNightCars}", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(6.dp))
                        LinearProgressIndicator(
                            progress = { (ui.todayCars.toFloat() / max(1, ui.dayGoal)).coerceIn(0f, 1f) },
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                )
                SummaryCard(
                    modifier = Modifier.weight(1f),
                    label = "今日收入",
                    value = formatMoney(ui.todayIncome, ui.hideAmt),
                    valueColor = Green,
                    footer = {
                        Spacer(Modifier.height(12.dp))
                        Text("昨日合计 ${ui.yestCars}车 · " + formatMoney(ui.yestIncome, ui.hideAmt),
                            fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                )
            }
        }

        if (ui.yestTypeCounts.isNotEmpty()) {
            item { SectionTitle("昨天作业类型车数") }
            item {
                GroupedCard {
                    ui.types.forEach { t ->
                        val c = ui.yestTypeCounts[t.id] ?: 0
                        if (c > 0) {
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    TypeDot(t.color); Spacer(Modifier.width(6.dp)); Text(t.name)
                                }
                                Text("${c}车 · " + formatMoney(c * t.price, ui.hideAmt), fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
            }
            item { SectionTitle("复制昨日") }
            item {
                GroupedCard {
                    CopyRow("全部昨日数据 (${ui.yestNames.size}条)") { scope.launch { viewModel.copyYesterday("all"); scope.toast("已复制昨日数据") } }
                    ui.yestNames.forEach { name ->
                        CopyRow("复制 $name") { scope.launch { viewModel.copyYesterday(name); scope.toast("已复制 $name 的数据") } }
                    }
                }
            }
        }

        item { SectionTitle("今日记录") }
        if (ui.todayRecords.isEmpty()) {
            item { Text("今天还没有记录", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth().padding(38.dp), textAlign = TextAlign.Center) }
        } else {
            items(ui.todayRecords) { rec ->
                RecordCard(
                    record = rec, types = ui.types, prices = prices, hideAmt = ui.hideAmt,
                    onEdit = { viewModel.editRecord(rec.id) },
                    onDelete = { pendingDelete = rec }
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

@Composable
private fun StepperRow(
    type: WorkType,
    count: Int,
    hideAmt: Boolean,
    onStep: (Int) -> Unit,
    onSet: (Int) -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TypeDot(type.color)
            Spacer(Modifier.width(8.dp))
            Text(type.name, fontWeight = FontWeight.Bold)
            Spacer(Modifier.width(6.dp))
            Text(formatMoney(type.price, hideAmt) + "/车", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            RepeatButton(delta = -1, onStep = onStep, containerColor = Red.copy(alpha = 0.12f), contentColor = Red) {
                Icon(Icons.Filled.Remove, contentDescription = "减少")
            }
            OutlinedTextField(
                value = count.toString(),
                onValueChange = { it.toIntOrNull()?.let(onSet) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true,
                textStyle = LocalTextStyle.current.copy(textAlign = TextAlign.Center),
                modifier = Modifier
                    .width(64.dp)
                    .pointerInput(Unit) {
                        // Non-consuming double-tap detection so the field keeps
                        // its editing focus (PRD §2.2: 双击清零).
                        var lastTap = 0L
                        awaitPointerEventScope {
                            while (true) {
                                val event = awaitPointerEvent(PointerEventPass.InitialPass)
                                val change = event.changes.firstOrNull() ?: continue
                                if (change.pressed) {
                                    val now = System.currentTimeMillis()
                                    if (now - lastTap in 1..300) {
                                        onSet(0)
                                        lastTap = 0
                                    } else {
                                        lastTap = now
                                    }
                                }
                            }
                        }
                    }
            )
            RepeatButton(delta = 1, onStep = onStep, containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), contentColor = MaterialTheme.colorScheme.primary) {
                Icon(Icons.Filled.Add, contentDescription = "增加")
            }
            TextButton(onClick = { onStep(5) }) { Text("+5") }
            TextButton(onClick = { onStep(10) }) { Text("+10") }
        }
    }
}

/**
 * Tactile +/- button (PRD §2.2 / §5): a single tap steps by [delta], a long press
 * (after a 400ms delay) repeats every 100ms, and the button scales to 0.88 while
 * pressed for physical-press feedback.
 */
@Composable
private fun RepeatButton(
    delta: Int,
    onStep: (Int) -> Unit,
    containerColor: Color,
    contentColor: Color,
    content: @Composable () -> Unit
) {
    var pressed by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(targetValue = if (pressed) 0.88f else 1f, label = "stepperScale")
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(40.dp)
            .clip(CircleShape)
            .background(containerColor)
            .scale(scale)
            .pointerInput(delta) {
                detectTapGestures(
                    onPress = {
                        pressed = true
                        var repeated = false
                        val job = launch {
                            delay(400)
                            repeated = true
                            while (true) {
                                onStep(delta)
                                delay(100)
                            }
                        }
                        val released = tryAwaitRelease()
                        job.cancel()
                        pressed = false
                        if (!released) return@detectTapGestures
                        if (!repeated) onStep(delta)
                    }
                )
            }
    ) { content() }
}

@Composable
private fun CopyRow(label: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label)
        TextButton(onClick = onClick, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.primary)) {
            Text("复制")
        }
    }
}
