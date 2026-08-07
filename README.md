# 货场作业记账 · Android 原生版

将原本的 **iOS 风格 PWA（HTML）** 完整移植为 **原生 Android 应用**（Kotlin + Jetpack Compose + Material 3 + Room）。
保留了原网页的全部核心功能，并把浏览器 `localStorage` 改为真正的离线本地数据库，导出/导入改用 Android 原生文件分享。

> 包名：`com.huochang.yard` ｜ 最低版本：Android 8.0 (API 26) ｜ 目标：API 34

---

## 功能对照（HTML → Android）

| 原网页模块 | 原生实现 |
|-----------|---------|
| 今日 · 快速记账（日期/姓名/车号/班次 + 各类型计数器） | `TodayScreen` + 步进器 + 智能合并 |
| 今日摘要（车数 / 收入 / 目标进度 / 昨日对比） | `TodayViewModel` 实时聚合 |
| 复制昨日 | `repository.copyYesterday()` |
| 明细 · 近7天矩阵、日期/班次筛选、搜索、排序 | `DetailsScreen` |
| 明细 · 批量选择 / 删除 / 导出 CSV | 复选框 + `FileSharer` 分享 |
| 月报 · 月度统计、每日柱状图、按单价/类型/人员汇总、工资预估 | `ReportScreen` + 自定义柱状图 |
| 设置 · 个人信息、单价、作业类型管理、工资构成、主题色、目标 | `SettingsScreen` |
| 设置 · JSON 备份 / CSV 导入 / 示例数据 / 清空 | `FileSharer` + `ActivityResultContracts` |
| PWA Service Worker / 添加到主屏幕 | 不再需要（本身就是原生 App） |

---

## 架构

```
com.huochang.yard
├── YardApplication.kt            # 初始化 Room + Repository（单例）
├── MainActivity.kt               # 入口 Activity
├── ui
│   ├── MainScreen.kt             # Scaffold：顶栏 + 底部导航(4 Tab) + 主题
│   ├── BaseYardViewModel.kt      # 暴露共享 Repository
│   ├── theme/Theme.kt            # Material3 主题（强调色=可配置 tint）
│   ├── components/Components.kt  # SectionTitle / GroupedCard / RecordCard / DateField / 等
│   ├── today/                    # TodayScreen.kt (+ ViewModel)
│   ├── details/                  # DetailsScreen.kt (+ ViewModel)
│   ├── report/                   # ReportScreen.kt (+ ViewModel)
│   └── settings/                 # SettingsScreen.kt + SettingsViewModel.kt
├── data
│   ├── model/DomainModels.kt     # 领域模型（WorkType / YardRecord / Profile / Salary / AppConfig）
│   ├── local/                    # Room：Entities / Converters / DAOs / AppDatabase
│   ├── YardRepository.kt         # 唯一数据源（Flow + 智能合并 + 导入导出）
│   └── (DI 通过 Application 单例，无需 Hilt)
└── util                          # DateUtils / Calculations / FileSharer
```

### 关键设计决策
- **离线优先**：`localStorage` → **Room**（records / work_types / profile / salary / app_config 五张表）。
- **响应式 UI**：记录、类型、配置均以 `StateFlow` 暴露，Compose 自动重绘。
- **可配置主题色**：沿用原网页的 `--blue` tint 思路，主题主色由用户选择的 accent 决定。
- **导出/导入**：PWA 的浏览器下载 → Android `FileProvider` + 系统分享面板（CSV 带 UTF-8 BOM，Excel 不乱码）。
- **智能合并**：同 日期+姓名+车号+班次 的记录自动累加车数（与原网页逻辑一致）。
- **撤销**：删除操作支持一次性撤销（顶栏 ↩ 按钮）。

---

## 构建与运行

### 方式一：Android Studio（推荐）
1. 用 **Android Studio Hedgehog / Iguana 或更新版本** 打开 `YardAccounting` 目录。
2. 等待 Gradle 同步（会自动下载 Gradle 8.2 与依赖）。
3. 连接设备或启动模拟器（API ≥ 26）。
4. 点击 ▶ Run，或直接 `Build → Build Bundle(s) / APK(s) → Build APK`。

### 方式二：命令行（含一键构建签名脚本）
```bash
# 若本机已安装 Gradle 8.x
./gradlew assembleDebug   # 产出 app/build/outputs/apk/debug/app-debug.apk
./gradlew installDebug    # 直接安装到已连接设备
```

#### 🔧 一键构建并签名 release APK
仓库根目录提供 `build_and_sign.sh`，**自动完成**：检测 Android SDK →（缺失则）生成
release.keystore → 写入 `local.properties` 签名配置 → 执行 `assembleRelease` → 把签名 APK 复制到
`app/release/`。

```bash
./build_and_sign.sh                 # 默认配置，签名信息存于 keystore/（已 gitignore）
KEY_ALIAS=mykey ./build_and_sign.sh # 自定义 key alias
adb install -r app/release/app-release.apk   # 装到已连接设备
```

> 前置：本机需有 Android Studio（自带 Gradle+SDK）或独立的 Gradle 8.x + Android SDK（设好
> `ANDROID_HOME`）。签名信息只写进 `local.properties` 与 `keystore/`，二者均已被 `.gitignore` 忽略，
> **不会进版本库**，请妥善保管你的 keystore（丢失将无法更新已上架的 App）。

### 技术栈版本
- Kotlin 1.9.22 ｜ AGP 8.2.2 ｜ Compose BOM 2024.02.00
- Room 2.6.1（KSP）｜ Lifecycle 2.7.0 ｜ kotlinx.serialization 1.6.2

---

## 与原网页的差异 / 简化
- 顶栏的「撤销」仅覆盖**删除**类操作（原网页为全量快照撤销）；其余编辑通过表单回填实现。
- 明细页的记录**编辑**留在「今日」页处理（明细页提供删除/选择/导出），避免跨 Tab 状态耦合。
- 移除了 PWA 的 Service Worker / Manifest / 安装引导（原生应用本身即「已安装」）。
- 自动 7 天备份快照（`hc_bk`）未移植；改为 JSON 手动备份/恢复，更符合原生习惯。

---

## 目录速览
```
YardAccounting/
├── settings.gradle.kts
├── build.gradle.kts
├── gradle.properties
├── gradle/wrapper/gradle-wrapper.properties
├── app/
│   ├── build.gradle.kts
│   ├── proguard-rules.pro
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/huochang/yard/...
│       └── res/ (values / drawable / mipmap / xml)
└── README.md
```

---

## 发布到 GitHub

仓库根目录提供 `push_to_github.sh`，在本机**联网且已登录 gh** 的环境一键建仓并推送：

```bash
# 首次需登录并配置身份
gh auth login
git config --global user.name  "你的名字"
git config --global user.email "you@example.com"

./push_to_github.sh                              # 默认建私有仓库 yard-accounting-android
REPO_VISIBILITY=public ./push_to_github.sh       # 改为公开仓库
```

> keystore/ 与 local.properties 已被 `.gitignore` 忽略，推送时**不会**泄露签名密钥。

---

## 在线构建 APK（GitHub Actions，免装 Android Studio）

仓库已内置 `.github/workflows/build-apk.yml`：**把仓库推到 GitHub 后，云端自动编译并产出 APK**，你只需下载。

流程：
1. 按上节把仓库推到 GitHub（`push_to_github.sh`）。
2. 进入仓库 **Actions → Build APK**，等待运行完成（约 3–5 分钟）。
3. 在运行结果的 **Artifacts** 里下载 `app-debug.apk`，传到手机安装即可。

> 默认出 **debug APK**（可直接安装测试，无需签名）。若要**签名 release APK** 上架，
> 按 workflow 文件底部的注释，在仓库 `Settings → Secrets` 配置 `KEYSTORE_BASE64` 等后用
> `assembleRelease`（脚本已写好，取消注释即可）。

---

## 一键脚本清单
| 脚本 / 配置 | 作用 | 运行环境 |
|------|------|---------|
| `build_and_sign.sh` | 生成 keystore + 签名 + 构建 release APK | 本机（需 Android SDK） |
| `push_to_github.sh`  | 建 GitHub 仓库并推送 | 本机（需联网 + `gh` 登录） |
| `.github/workflows/build-apk.yml` | 推送到 GitHub 后云端自动构建 APK | GitHub Actions（无需本机 SDK） |
