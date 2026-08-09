package com.huochang.yard.ui.settings

import android.app.Application
import com.huochang.yard.data.model.AppConfig
import com.huochang.yard.data.model.Profile
import com.huochang.yard.data.model.Salary
import com.huochang.yard.data.model.WorkType
import com.huochang.yard.ui.BaseYardViewModel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class SettingsViewModel(application: Application) : BaseYardViewModel(application) {

    data class SettingsUiState(
        val profile: Profile = Profile("", "", "主货场"),
        val salary: Salary = Salary(0.0, 0.0, 0.0, 0.0, 0.0),
        val config: AppConfig = AppConfig("system", "#007AFF", false, 100, 2500, "", "", "day"),
        val types: List<WorkType> = emptyList()
    )

    val uiState = combine(repo.profile, repo.salary, repo.config, repo.workTypes) { p, s, c, t ->
        SettingsUiState(p, s, c, t)
    }.stateIn(viewModelScope, kotlinx.coroutines.flow.SharingStarted.WhileSubscribed(5000), SettingsUiState())

    fun saveProfile(name: String, car: String, site: String) {
        viewModelScope.launch { repo.saveProfile(Profile(name, car, site)) }
    }

    fun saveSalary(base: Double, meal: Double, night: Double, bonus: Double, deduct: Double) {
        viewModelScope.launch { repo.saveSalary(Salary(base, meal, night, bonus, deduct)) }
    }

    fun saveGoals(dayGoal: Int, moGoal: Int) {
        viewModelScope.launch { repo.saveConfig(repo.config.value.copy(dayGoal = dayGoal, moGoal = moGoal)) }
    }

    fun setTint(color: String) {
        viewModelScope.launch { repo.saveConfig(repo.config.value.copy(tint = color)) }
    }

    fun toggleHideAmount() {
        viewModelScope.launch { repo.saveConfig(repo.config.value.copy(hideAmt = !repo.config.value.hideAmt)) }
    }

    fun updatePrice(id: String, price: Double) {
        viewModelScope.launch { repo.updatePrice(id, price) }
    }

    fun addType(name: String, price: Double) {
        viewModelScope.launch { runCatching { repo.addWorkType(name, price) } }
    }

    fun deleteType(id: String) {
        viewModelScope.launch { repo.deleteWorkType(id) }
    }

    suspend fun exportJson(): String = repo.buildJsonBackup()

    suspend fun importJsonText(text: String) = repo.importJson(text)

    suspend fun importCsvText(text: String): Int = repo.importCsv(text)

    suspend fun loadSample() = repo.loadSampleData()

    suspend fun clearAll() = repo.clearAll()
}
