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

> 默认出 **debug APK**（可直接安装测试，无需签名）。若想要**你自己密钥签名的 release 包**
> （可上架 / 正式分发），见下方「在线出已签名 APK」一节。

---

## 在线构建 APK（Codemagic，另一种选择）

如果你嫌 GitHub Actions 总报错，本项目也内置了 `codemagic.yaml`，支持在 **Codemagic** 平台在线出包：

| 工作流 | 作用 | 是否需要签名 |
|---|---|---|
| **Yard Debug APK** | 出 debug 测试包 | 否 |
| **Yard Signed Release APK** | 出签名 release 包 | 是（在 Codemagic 上传 keystore） |

详细步骤（上传 keystore、运行构建、下载 APK）见 **《Codemagic使用说明.md》**。

---

## 🔐 在线出已签名 APK（GitHub Actions，免本地签名）

> 嫌下面步骤太简略？同目录有 **《在线签名详细教程.md》** —— 专门给不熟命令的同学准备的图文版（含 Android Studio 图形生成密钥、GitHub 网页填 Secrets 逐屏指引）。

workflow 已内置**条件签名**：你在仓库配置好签名密钥后，云端会自动额外产出一个用你自己的
密钥签名的 `app-release.apk`；**没配置则只出 debug 包，不会报错**。全程无需本机装 Android Studio 签名。

### 准备一次（只需做一次）

**① 生成 keystore**（JDK 自带 `keytool`，或用 Android Studio 的 `Build → Generate Signed Bundle / APK`）：
```bash
keytool -genkey -v -keystore release.keystore -alias yardrelease \
        -keyalg RSA -keysize 2048 -validity 10000
```
> Windows 用户建议在 **Git Bash** 里跑这条命令；过程中会让你设密码并填一些信息，
> **密码务必牢记**（alias 默认用 `yardrelease`）。

**② 转成 base64 文本**：
```bash
base64 -w0 release.keystore > release.keystore.b64
```
> Windows 没有 `base64` 命令时，用 Git Bash 跑上面这条；或用
> `certutil -encode release.keystore release.keystore.b64` 后删掉首尾两行再合并为一行。

**③ 填进 GitHub Secrets**：仓库 `Settings → Secrets and variables → Actions → New repository secret`，
添加以下 4 条：

| Secret 名称 | 值 |
|------|-----|
| `KEYSTORE_BASE64` | `release.keystore.b64` 的**全部内容**（一整段） |
| `KEY_ALIAS` | `yardrelease` |
| `KEY_PASSWORD` | 你第①步设的**密钥密码** |
| `STORE_PASSWORD` | 你第①步设的**库密码** |

### 之后怎么用
推送代码后，进入仓库 **Actions → Build APK**，运行结束会在 **Artifacts** 里多出 `app-release`
（已签名，可上架/正式分发），同时仍有 `app-debug`。

> ⚠️ **密钥安全**：`release.keystore` 和那段 base64 文本**等同于你的签名身份**——
> 务必在本地备份好（**丢失将无法更新已上架的 App**），且**绝对不要提交进仓库**
> （已在 `.gitignore` 忽略 `keystore/` 与 `local.properties`）。

---

## 不想用 GitHub 云端构建？本地出包 + 手动传 Release

如果你遇到 GitHub Actions 构建报错、或单纯不想依赖云端编译，完全可以**不在 GitHub 上构建**——
在自己电脑上编译好 APK，再把成品传到 GitHub 的 **Release** 里当"网盘"用。GitHub 只负责存代码和分发，
**不会触发任何构建检查**，自然没有 Actions 红叉。

### 步骤一：本机出包（任选一种）
- **Android Studio（最省心）**：打开项目 → 等同步完成 → 菜单
  `Build → Build Bundle(s) / APK(s) → Build APK`，右下角弹窗点 `locate` 即可拿到
  `app/build/outputs/apk/debug/app-debug.apk`。
- **命令行**：本机配好 Android SDK 后执行 `./gradlew assembleDebug`（或用 `./build_and_sign.sh`
  出签名版 release APK，见上方"方式二"）。

### 步骤二：手动传到 GitHub Release
1. 打开你的 GitHub 仓库页面 → 右侧 **Releases → Draft a new release**。
2. 填个版本号（如 `v1.0-debug`），把上一步的 `app-debug.apk` 拖进附件区。
3. 点 **Publish release**，别人就能在 Release 页面直接下载安装。

> 这样 GitHub 一次构建都没跑，所有 Actions 报错都不会出现。仓库里常见的 **Dependabot 漏洞提示**
> 属于"依赖体检"而非编译错误（提醒你升级第三方库版本），可单独决定是否处理，不影响你出包安装。
> 若想彻底关掉自动构建，删除 `.github/workflows/build-apk.yml` 即可。

---

## 一键脚本清单
| 脚本 / 配置 | 作用 | 运行环境 |
|------|------|---------|
| `build_and_sign.sh` | 生成 keystore + 签名 + 构建 release APK | 本机（需 Android SDK） |
| `push_to_github.sh`  | 建 GitHub 仓库并推送 | 本机（需联网 + `gh` 登录） |
| `.github/workflows/build-apk.yml` | 推送到 GitHub 后云端自动构建 APK | GitHub Actions（无需本机 SDK） |
