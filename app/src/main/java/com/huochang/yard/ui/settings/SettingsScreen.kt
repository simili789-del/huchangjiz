package com.huochang.yard.ui.settings

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.huochang.yard.data.model.TINT_OPTIONS
import com.huochang.yard.ui.components.*
import com.huochang.yard.util.FileSharer
import com.huochang.yard.util.todayStr
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(viewModel: SettingsViewModel = viewModel()) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val ui by viewModel.uiState.collectAsStateWithLifecycle()

    var name by remember { mutableStateOf("") }
    var car by remember { mutableStateOf("") }
    var site by remember { mutableStateOf("") }
    var base by remember { mutableStateOf("") }
    var meal by remember { mutableStateOf("") }
    var night by remember { mutableStateOf("") }
    var bonus by remember { mutableStateOf("") }
    var deduct by remember { mutableStateOf("") }
    var dayGoal by remember { mutableStateOf("") }
    var moGoal by remember { mutableStateOf("") }
    var newTypeName by remember { mutableStateOf("") }
    var newTypePrice by remember { mutableStateOf("") }
    var pendingDeleteType by remember { mutableStateOf<String?>(null) }
    var pendingClear by remember { mutableStateOf(false) }

    LaunchedEffect(ui) {
        name = ui.profile.name
        car = ui.profile.car
        site = ui.profile.site
        base = ui.salary.base.toString()
        meal = ui.salary.meal.toString()
        night = ui.salary.night.toString()
        bonus = ui.salary.bonus.toString()
        deduct = ui.salary.deduct.toString()
        dayGoal = ui.config.dayGoal.toString()
        moGoal = ui.config.moGoal.toString()
    }

    val jsonLauncher = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult
        val text = context.contentResolver.openInputStream(uri)?.use { it.bufferedReader().readText() }
        if (text != null) scope.launch {
            runCatching { viewModel.importJsonText(text) }
                .onSuccess { scope.toast("已恢复 JSON 数据") }
                .onFailure { scope.toast("JSON 解析失败") }
        }
    }
    val csvLauncher = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult
        val text = context.contentResolver.openInputStream(uri)?.use { it.bufferedReader().readText() }
        if (text != null) scope.launch {
            val n = runCatching { viewModel.importCsvText(text) }.getOrDefault(0)
            scope.toast("成功导入 $n 条记录")
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        item { SectionTitle("个人信息") }
        item {
            GroupedCard {
                FormRow("默认姓名") { OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), singleLine = true, placeholder = { Text("李四明") }) }
                FormRow("默认车号") { OutlinedTextField(car, { car = it }, Modifier.fillMaxWidth(), singleLine = true, placeholder = { Text("港30") }) }
                FormRow("货场名称") { OutlinedTextField(site, { site = it }, Modifier.fillMaxWidth(), singleLine = true, placeholder = { Text("主货场") }) }
            }
        }
        item {
            Button(onClick = { viewModel.saveProfile(name, car, site); scope.toast("个人信息已保存") },
                modifier = Modifier.fillMaxWidth().height(44.dp), shape = MaterialTheme.shapes.small) { Text("保存个人信息") }
        }

        item { SectionTitle("单价设置 (元/车)") }
        item {
            GroupedCard {
                ui.types.forEach { t ->
                    FormRow(t.name) {
                        OutlinedTextField(
                            value = t.price.toString(),
                            onValueChange = { v -> viewModel.updatePrice(t.id, v.toDoubleOrNull() ?: 0.0) },
                            modifier = Modifier.width(100.dp),
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            textStyle = LocalTextStyle.current.copy(textAlign = androidx.compose.ui.text.style.TextAlign.End)
                        )
                    }
                }
            }
        }

        item { SectionTitle("作业类型管理") }
        item {
            GroupedCard {
                ui.types.forEach { t ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            TypeDot(t.color); Spacer(Modifier.width(6.dp))
                            Text("${t.name} (${t.price}元/车)")
                        }
                        TextButton(onClick = { pendingDeleteType = t.id }, colors = ButtonDefaults.textButtonColors(contentColor = Red)) { Text("删除") }
                    }
                }
            }
        }
        item {
            GroupedCard {
                Text("新增作业类型", fontWeight = FontWeight.Bold, fontSize = 14.sp, modifier = Modifier.padding(start = 16.dp, top = 12.dp))
                Row(modifier = Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(newTypeName, { newTypeName = it }, Modifier.weight(1f), singleLine = true, placeholder = { Text("类型名称") })
                    OutlinedTextField(newTypePrice, { newTypePrice = it }, Modifier.width(90.dp), singleLine = true,
                        placeholder = { Text("单价") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
                }
                Button(onClick = {
                    if (newTypeName.isBlank()) { scope.toast("请输入类型名称"); return@Button }
                    viewModel.addType(newTypeName, newTypePrice.toDoubleOrNull() ?: 0.0)
                    newTypeName = ""; newTypePrice = ""
                    scope.toast("已添加作业类型")
                }, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, bottom = 12.dp).height(40.dp), shape = MaterialTheme.shapes.small) { Text("添加类型") }
            }
        }

        item { SectionTitle("工资构成设置") }
        item {
            GroupedCard {
                FormRow("基本底薪") { NumField(base, { base = it }) }
                FormRow("餐补") { NumField(meal, { meal = it }) }
                FormRow("加班") { NumField(night, { night = it }) }
                FormRow("工龄/奖金") { NumField(bonus, { bonus = it }) }
                FormRow("扣款") { NumField(deduct, { deduct = it }) }
            }
        }
        item {
            Button(onClick = {
                viewModel.saveSalary(base.toDoubleOrNull() ?: 0.0, meal.toDoubleOrNull() ?: 0.0, night.toDoubleOrNull() ?: 0.0, bonus.toDoubleOrNull() ?: 0.0, deduct.toDoubleOrNull() ?: 0.0)
                scope.toast("工资构成已保存")
            }, modifier = Modifier.fillMaxWidth().height(44.dp), shape = MaterialTheme.shapes.small) { Text("保存工资设置") }
        }

        item { SectionTitle("外观设置") }
        item {
            GroupedCard {
                Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                    Text("主题颜色", fontWeight = FontWeight.Medium)
                    Spacer(Modifier.height(10.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        TINT_OPTIONS.forEach { c ->
                            val selected = ui.config.tint.equals(c, ignoreCase = true)
                            Box(
                                modifier = Modifier
                                    .size(32.dp)
                                    .clip(CircleShape)
                                    .background(Color.fromHex(c))
                                    .then(if (selected) Modifier.border(3.dp, MaterialTheme.colorScheme.onSurface, CircleShape) else Modifier)
                                    .clickable { viewModel.setTint(c) }
                            )
                        }
                    }
                }
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("隐藏金额")
                    Switch(checked = ui.config.hideAmt, onCheckedChange = { viewModel.toggleHideAmount() })
                }
            }
        }

        item { SectionTitle("目标与参数") }
        item {
            GroupedCard {
                FormRow("每日目标车数") { NumField(dayGoal, { dayGoal = it }) }
                FormRow("每月目标车数") { NumField(moGoal, { moGoal = it }) }
            }
        }
        item {
            Button(onClick = {
                viewModel.saveGoals(dayGoal.toIntOrNull() ?: 100, moGoal.toIntOrNull() ?: 2500)
                scope.toast("目标设置已保存")
            }, modifier = Modifier.fillMaxWidth().height(44.dp), shape = MaterialTheme.shapes.small) { Text("保存目标设置") }
        }

        item { SectionTitle("数据安全与备份") }
        item {
            GroupedCard(modifier = Modifier.padding(14.dp)) {
                SettingsAction("导出 JSON 备份") { scope.launch { val json = viewModel.exportJson(); FileSharer.shareText(context, "货场记账备份_${todayStr()}.json", json, "application/json") } }
                SettingsAction("从 JSON 恢复") { jsonLauncher.launch("application/json") }
                SettingsAction("从 CSV 导入记录") { csvLauncher.launch("text/csv") }
                SettingsAction("恢复示例数据") { scope.launch { viewModel.loadSample(); scope.toast("已载入示例数据") } }
                SettingsAction("清空全部数据", danger = true) { pendingClear = true }
            }
        }
        item { Spacer(Modifier.height(16.dp)) }
    }

    pendingDeleteType?.let { id ->
        AlertDialog(
            onDismissRequest = { pendingDeleteType = null },
            title = { Text("删除作业类型") },
            text = { Text("删除该作业类型后，相关记录中的该类型车数将被清空。是否继续？") },
            confirmButton = {
                TextButton(onClick = { scope.launch { viewModel.deleteType(id) }; pendingDeleteType = null; scope.toast("已删除类型") },
                    colors = ButtonDefaults.textButtonColors(contentColor = Red)) { Text("确认删除") }
            },
            dismissButton = { TextButton(onClick = { pendingDeleteType = null }) { Text("取消") } }
        )
    }

    if (pendingClear) {
        AlertDialog(
            onDismissRequest = { pendingClear = false },
            title = { Text("清空数据") },
            text = { Text("确定要清空本机保存的所有记账记录与数据吗？此操作不可恢复！") },
            confirmButton = {
                TextButton(onClick = { scope.launch { viewModel.clearAll() }; pendingClear = false; scope.toast("已清空所有数据") },
                    colors = ButtonDefaults.textButtonColors(contentColor = Red)) { Text("确认清空") }
            },
            dismissButton = { TextButton(onClick = { pendingClear = false }) { Text("取消") } }
        )
    }
}

@Composable
private fun NumField(value: String, onValueChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.width(120.dp),
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        textStyle = LocalTextStyle.current.copy(textAlign = androidx.compose.ui.text.style.TextAlign.End)
    )
}

@Composable
private fun SettingsAction(label: String, danger: Boolean = false, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, color = if (danger) Red else MaterialTheme.colorScheme.onSurface)
        Text(if (danger) "清空" else "执行", color = if (danger) Red else MaterialTheme.colorScheme.primary)
    }
}
