package com.huochang.yard.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.huochang.yard.YardApplication
import com.huochang.yard.data.YardRepository
import kotlinx.coroutines.launch

/** Base ViewModel that exposes the shared [YardRepository] from the Application. */
abstract class BaseYardViewModel(application: Application) : AndroidViewModel(application) {
    protected val repo: YardRepository
        get() = (getApplication<YardApplication>()).repository

    /** Restore the most recently deleted record(s) (PRD top-bar 撤销). */
    fun undoDelete() {
        viewModelScope.launch { repo.undoDelete() }
    }
}
