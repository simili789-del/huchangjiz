package com.huochang.yard

import android.app.Application
import androidx.room.Room
import com.huochang.yard.data.YardRepository
import com.huochang.yard.data.local.AppDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class YardApplication : Application() {

    val database by lazy {
        Room.databaseBuilder(
            this,
            AppDatabase::class.java,
            AppDatabase.DATABASE_NAME
        ).build()
    }

    val repository by lazy { YardRepository(database) }

    override fun onCreate() {
        super.onCreate()
        // Seed default work types / config on first launch (off the main thread).
        CoroutineScope(Dispatchers.IO).launch {
            repository.initData()
        }
    }
}
