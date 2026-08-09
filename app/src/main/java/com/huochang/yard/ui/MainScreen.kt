package com.huochang.yard.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.huochang.yard.data.YardRepository
import com.huochang.yard.ui.components.DynamicIslandToast
import com.huochang.yard.ui.components.toast
import com.huochang.yard.ui.details.DetailsScreen
import com.huochang.yard.ui.report.ReportScreen
import com.huochang.yard.ui.settings.SettingsScreen
import com.huochang.yard.ui.theme.YardAppTheme
import com.huochang.yard.ui.today.TodayScreen
import com.huochang.yard.util.headerDateString
import kotlinx.coroutines.launch

private enum class Tab(val key: String, val label: String) {
    TODAY("today", "今日"),
    DETAILS("details", "明细"),
    REPORT("report", "月报"),
    SETTINGS("settings", "设置")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(repository: YardRepository) {
    val config by repository.config.collectAsStateWithLifecycle()
    val profile by repository.profile.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableStateOf(Tab.TODAY) }
    val scope = rememberCoroutineScope()

    val darkTheme = when (config.theme) {
        "dark" -> true
        "light" -> false
        else -> isSystemInDarkTheme()
    }

    YardAppTheme(tintHex = config.tint, darkTheme = darkTheme) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Surface(
                                color = MaterialTheme.colorScheme.primary,
                                shape = CircleShape,
                                modifier = Modifier.size(34.dp)
                            ) {
                                Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                                    Text("记", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                                }
                            }
                            Spacer(Modifier.width(10.dp))
                            Column {
                                Text(
                                    text = profile.site.ifBlank { "货场作业记账" },
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold
                                )
                                Text(
                                    text = headerDateString(),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    },
                        actions = {
                            IconButton(onClick = {
                                if (repository.canUndoDelete()) {
                                    scope.launch { repository.undoDelete() }
                                    scope.toast("已撤销删除")
                                } else {
                                    scope.toast("没有可撤销的操作")
                                }
                            }) {
                                Icon(Icons.Filled.Undo, contentDescription = "撤销")
                            }
                            IconButton(onClick = {
                                val next = if (darkTheme) "light" else "dark"
                                scope.launch { repository.saveConfig(config.copy(theme = next)) }
                            }) {
                                Icon(
                                    if (darkTheme) Icons.Filled.LightMode else Icons.Filled.DarkMode,
                                    contentDescription = "切换主题"
                                )
                            }
                        },
                        colors = TopAppBarDefaults.topAppBarColors(
                            containerColor = MaterialTheme.colorScheme.background
                        )
                    )
                },
                bottomBar = {
                    NavigationBar {
                        Tab.entries.forEach { t ->
                            val selected = t == tab
                            NavigationBarItem(
                                selected = selected,
                                onClick = { tab = t },
                                icon = {
                                    Icon(
                                        when (t) {
                                            Tab.TODAY -> Icons.Filled.Home
                                            Tab.DETAILS -> Icons.Filled.List
                                            Tab.REPORT -> Icons.Filled.BarChart
                                            Tab.SETTINGS -> Icons.Filled.Settings
                                        },
                                        contentDescription = t.label
                                    )
                                },
                                label = { Text(t.label) }
                            )
                        }
                    }
                },
                snackbarHost = { }
            ) { innerPadding ->
                Box(
                    Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                ) {
                    when (tab) {
                        Tab.TODAY -> TodayScreen()
                        Tab.DETAILS -> DetailsScreen()
                        Tab.REPORT -> ReportScreen()
                        Tab.SETTINGS -> SettingsScreen()
                    }
                    DynamicIslandToast()
                }
            }
        }
    }
