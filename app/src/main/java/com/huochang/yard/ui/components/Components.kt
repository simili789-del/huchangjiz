@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.huochang.yard.ui.components

import android.app.DatePickerDialog
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.huochang.yard.data.model.SHIFT_DAY
import com.huochang.yard.data.model.SHIFT_NIGHT
import com.huochang.yard.util.recordCars
import com.huochang.yard.util.recordMoney
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import java.util.Calendar
import com.huochang.yard.ui.theme.*

/**
 * Dynamic-Island style toast (PRD §5): a centered, blur-dark floating pill with
 * an optional inline action (e.g. 撤销). Driven by a shared bus so any screen can
 * emit a message without holding a SnackbarHost reference.
 */
data class YardToast(
    val message: String,
    val actionLabel: String? = null,
    val onAction: (() -> Unit)? = null
)

val yardToastBus = MutableSharedFlow<YardToast>(extraBufferCapacity = 8)

/** Emit a short toast. Pass [actionLabel]/[onAction] to show an inline action. */
fun CoroutineScope.toast(
    message: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null
) {
    yardToastBus.tryEmit(YardToast(message, actionLabel, onAction))
}

fun formatMoney(amount: Double, hide: Boolean, prefix: String = "¥"): String =
    if (hide) prefix + "•••" else prefix + "%.2f".format(amount)

fun formatCount(n: Int, hide: Boolean): String =
    if (hide) "••" else n.toString()

@Composable
fun SectionTitle(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 12.dp, top = 20.dp, bottom = 6.dp)
    )
}

@Composable
fun GroupedCard(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(content = content)
    }
}

@Composable
fun FormRow(
    label: String,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.width(88.dp)
        )
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            content()
        }
    }
}

@Composable
fun TypeDot(colorHex: String) {
    Box(
        modifier = Modifier
            .size(10.dp)
            .clip(CircleShape)
            .background(Color.fromHex(colorHex))
    )
}

@Composable
fun ShiftTag(shift: String) {
    val isNight = shift == "night"
    val bg = if (isNight) Indigo.copy(alpha = 0.12f) else Orange.copy(alpha = 0.12f)
    val fg = if (isNight) Indigo else Orange
    Surface(
        color = bg,
        shape = RoundedCornerShape(6.dp)
    ) {
        Text(
            text = if (isNight) "夜班" else "白班",
            color = fg,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
        )
    }
}

/** A read-only date field (yyyy-MM-dd) that opens a native DatePickerDialog. */
@Composable
fun DateField(value: String, onValueChange: (String) -> Unit) {
    val context = LocalContext.current
    val cal = Calendar.getInstance()
    value.split("-").let { if (it.size == 3) cal.set(it[0].toInt(), it[1].toInt() - 1, it[2].toInt()) }
    val dialog = DatePickerDialog(
        context,
        { _, y, m, d -> onValueChange("%04d-%02d-%02d".format(y, m + 1, d)) },
        cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH)
    )
    OutlinedTextField(
        value = value,
        onValueChange = {},
        readOnly = true,
        singleLine = true,
        trailingIcon = { Icon(Icons.Filled.DateRange, contentDescription = null) },
        modifier = Modifier
            .fillMaxWidth()
            .clickable { dialog.show() },
        colors = OutlinedTextFieldDefaults.colors(
            unfocusedBorderColor = MaterialTheme.colorScheme.surfaceVariant,
            focusedBorderColor = MaterialTheme.colorScheme.primary
        )
    )
}

/** Day / Night segmented selector built from Material3 FilterChips. */
@Composable
fun ShiftSelector(shift: String, onShiftChange: (String) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterChip(
            selected = shift == SHIFT_DAY,
            onClick = { onShiftChange(SHIFT_DAY) },
            label = { Text("☀️ 白班") },
            modifier = Modifier.weight(1f)
        )
        FilterChip(
            selected = shift == SHIFT_NIGHT,
            onClick = { onShiftChange(SHIFT_NIGHT) },
            label = { Text("🌙 夜班") },
            modifier = Modifier.weight(1f)
        )
    }
}

/** A horizontal row of quick-filter chips, exactly one selected. */
@Composable
fun FilterChipRow(
    options: List<Pair<String, String>>,
    selected: String,
    onSelected: (String) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        options.forEach { (key, label) ->
            FilterChip(
                selected = selected == key,
                onClick = { onSelected(key) },
                label = { Text(label) }
            )
        }
    }
}

/**
 * A single record card used in the Today and Details lists.
 * Optionally shows a checkbox for batch selection.
 */
@Composable
fun RecordCard(
    record: com.huochang.yard.data.model.YardRecord,
    types: List<com.huochang.yard.data.model.WorkType>,
    prices: Map<String, Double>,
    hideAmt: Boolean,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    showCheck: Boolean = false,
    checked: Boolean = false,
    onToggleCheck: () -> Unit = {},
    showEdit: Boolean = true
) {
    val cars = recordCars(record.counts)
    val money = recordMoney(record.counts, prices)
    val typeStr = types
        .filter { (record.counts[it.id] ?: 0) > 0 }
        .joinToString(" · ") { "${it.name}${record.counts[it.id]}车" }

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(modifier = Modifier.padding(14.dp), verticalAlignment = Alignment.Top) {
            if (showCheck) {
                Checkbox(checked = checked, onCheckedChange = { onToggleCheck() })
            }
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(record.name, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                    Spacer(Modifier.width(8.dp))
                    ShiftTag(record.shift)
                }
                Spacer(Modifier.height(6.dp))
                Text(
                    "${record.date.substring(5)} · ${record.car.ifBlank { "无车号" }} $typeStr",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 13.sp
                )
                if (record.note.isNotBlank()) {
                    Text(record.note, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 11.sp)
                }
                Spacer(Modifier.height(6.dp))
                Row {
                    if (showEdit) {
                        TextButton(onClick = onEdit) {
                            Icon(Icons.Filled.Edit, contentDescription = null, modifier = Modifier.size(14.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("编辑")
                        }
                    }
                    TextButton(
                        onClick = onDelete,
                        colors = ButtonDefaults.textButtonColors(contentColor = Red)
                    ) {
                        Icon(Icons.Filled.Delete, contentDescription = null, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("删除")
                    }
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text("${cars}车", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                Text(formatMoney(money, hideAmt), color = Green, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/** Compact stat card used on the Today and Report summary grids. */
@Composable
fun SummaryCard(
    modifier: Modifier = Modifier,
    label: String,
    value: String,
    valueColor: Color = MaterialTheme.colorScheme.onSurface,
    footer: @Composable ColumnScope.() -> Unit = {}
) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(label, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.Bold)
            Text(value, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = valueColor, modifier = Modifier.padding(top = 4.dp))
            footer()
        }
    }
}

/**
 * Centered, blur-dark "Dynamic Island" toast (PRD §5). Shows the latest message
 * emitted on [yardToastBus] for ~2.6s, with an optional inline action button.
 * Place it once near the top of the screen content.
 */
@Composable
fun DynamicIslandToast(modifier: Modifier = Modifier) {
    var data by remember { mutableStateOf<YardToast?>(null) }
    var visible by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        yardToastBus.collect { toast ->
            data = toast
            visible = true
            delay(2600)
            visible = false
        }
    }

    Box(modifier = modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        AnimatedVisibility(
            visible = visible,
            enter = fadeIn() + slideInVertically { -it },
            exit = fadeOut() + slideOutVertically { -it }
        ) {
            data?.let { d ->
                Surface(
                    color = Color(0xE6000000),
                    shape = RoundedCornerShape(22.dp),
                    shadowElevation = 0.dp,
                    tonalElevation = 0.dp,
                    modifier = Modifier.padding(top = 10.dp, start = 16.dp, end = 16.dp)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 18.dp, vertical = 11.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(d.message, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                        if (d.actionLabel != null && d.onAction != null) {
                            Spacer(Modifier.width(10.dp))
                            TextButton(
                                onClick = {
                                    d.onAction.invoke()
                                    visible = false
                                },
                                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.primary)
                            ) {
                                Text(d.actionLabel, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }
        }
    }
}
