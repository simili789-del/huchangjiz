// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    id("com.android.application") version "8.2.2" apply false
    // 升级到 Kotlin 2.0.21：Compose 1.7.0 库是用 Kotlin 2.0 (K2 元数据) 编译的，
    // 旧的 Kotlin 1.9.24 (K1 编译器) 读不了 K2 元数据，导致 foundation.gestures.* 顶层符号
    // 部分解析失败（background/clickable 能解析，唯独 gestures 包缺失）—— 根因即在此。
    // K2 编译器向后兼容 K1 库，故升级后既能读 K2 的 Compose 1.7.0，也能读 K1 的其它依赖。
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.0.21" apply false
    id("com.google.devtools.ksp") version "2.0.21-1.0.27" apply false
    // Compose Compiler 2.0 已整合进 Kotlin 插件，不再用 composeOptions.kotlinCompilerExtensionVersion。
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
}
