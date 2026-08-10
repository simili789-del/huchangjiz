# 货场作业记账（Android App）

基于 Capacitor 的 Android 原生记账应用，前端为 HTML5 + CSS3 + Vanilla JavaScript（ES6），
通过 CodeMagic 在线 CI/CD 完成签名打包，直接生成 APK / AAB，无需本地安装 Android Studio。

## 目录结构

```
huochang_zhang/
├── www/                    # 前端 Web 应用（Capacitor webDir）
│   ├── index.html
│   ├── css/style.css
│   ├── js/app.js
│   ├── manifest.webmanifest
│   ├── icon.svg
│   └── sw.js
├── scripts/
│   └── postcap.py          # CI 中自动注入 AndroidManifest 权限 + Gradle 签名配置
├── capacitor.config.json
├── package.json
├── codemagic.yaml          # CodeMagic 工作流配置（发布版 + 调试版）
├── .gitignore
└── README.md
```

> **关于 `android/` 目录**：本仓库 **不包含** 预生成的 `android/` 原生工程目录（已在
> `.gitignore` 中排除）。CodeMagic 构建时会在线执行 `npx cap add android`，
> 由 Capacitor CLI 从 npm 实时生成最新、干净的原生工程，然后自动同步 Web 资源、
> 注入权限与签名配置，最后用 Gradle 打包。这样可以避免把体积庞大且容易过期的
> Gradle Wrapper / Android 原生模板文件提交到 Git，也保证每次构建使用的都是与
> `@capacitor/android` 版本匹配的原生工程模板。
>
> 如果你更希望本地长期持有 `android/` 目录（例如要手动改 Java 代码），可以本地执行
> 一次 `npx cap add android` 后把生成的目录提交到 Git，并从 `.gitignore` 中移除
> `android/`，之后 CodeMagic 脚本会自动识别目录已存在，改为执行 `npx cap sync android`
> 而不是重新创建。

## 一、在 CodeMagic 上打包（推荐，全程在线，无需本地环境）

### 1. 推送代码到 Git 仓库

```bash
git init
git add .
git commit -m "init: 货场作业记账"
git remote add origin <你的 GitHub/GitLab/Bitbucket 仓库地址>
git push -u origin main
```

### 2. 在 CodeMagic 创建项目

1. 登录 [codemagic.io](https://codemagic.io)，选择 **Add application**，关联你刚才推送的仓库。
2. CodeMagic 会自动识别根目录下的 `codemagic.yaml`，展示两个工作流：
   - **货场作业记账 - 发布版**（`huochang-release`）：生成签名 **Release APK + AAB**
   - **货场作业记账 - 调试版**（`huochang-debug`）：生成 **Debug APK**（无需签名，可直接安装测试）

### 3. 配置签名证书（仅发布版工作流需要）

发布版工作流需要 Android Keystore 才能生成可安装到用户设备 / 上架应用商店的签名包：

1. 若没有 keystore，先在本地生成一个（只需一次）：
   ```bash
   keytool -genkey -v -keystore huochang.keystore -alias huochang \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
2. 打开 CodeMagic 网页端 → **Team settings → Code signing identities → Android keystores**，
   上传该 `.keystore` 文件，填写 Keystore password / Key alias / Key password，
   保存后为其命名一个引用名称（Reference name），例如 `huochang_keystore`。
3. 确认该名称与 `codemagic.yaml` 中 `android_signing:` 下的名称一致
   （默认写的是 `huochang_keystore`，如改了名字请同步修改 `codemagic.yaml`）。
4. CodeMagic 会在构建时自动把证书解密并注入环境变量
   `CM_KEYSTORE_PATH / CM_KEYSTORE_PASSWORD / CM_KEY_ALIAS / CM_KEY_PASSWORD`，
   `scripts/postcap.py` 会读取这些变量并自动写入 `android/app/build.gradle` 的签名配置，
   全程无需手动编辑 Gradle 文件。
5. `codemagic.yaml` 中的 `groups: [keystore_credentials]` 与 `publishing.email.recipients`
   为占位配置：如果你不需要邮件通知产物，可以直接删除 `publishing` 段；
   `groups` 若未使用到额外变量也可以删除。

调试版工作流（`huochang-debug`）**不需要**任何签名配置，使用 Android 默认调试证书，
适合日常联调、内测安装。

### 4. 触发构建并下载 APK

- 推送代码到 `main` 分支会自动触发发布版构建；推送到任意分支都会触发调试版构建
  （可在 `codemagic.yaml` 的 `triggering.branch_patterns` 中调整）。
- 也可以在 CodeMagic 网页端手动点击 **Start new build** 选择工作流手动触发。
- 构建成功后，在构建详情页的 **Artifacts** 区域即可直接下载：
  - 发布版：`app-release.apk`、`app-release.aab`
  - 调试版：`app-debug.apk`
- 下载 APK 后传到手机安装即可（安装前需在手机「设置」中允许安装未知来源应用）。

## 二、本地构建（备选，需要本机安装 Node.js + JDK 17 + Android SDK）

```bash
npm install
npx cap add android      # 若已存在 android/ 目录可跳过，改为 npx cap sync android
python3 scripts/postcap.py
cd android
./gradlew assembleDebug          # 调试版
# 或
./gradlew assembleRelease        # 发布版（需先在 android/local.properties 或环境变量中配置签名）
```

生成的 APK 位于：
```
android/app/build/outputs/apk/debug/app-debug.apk
android/app/build/outputs/apk/release/app-release.apk
```

## 三、应用说明

- **技术栈**：HTML5 + CSS3 + 原生 ES6 JavaScript（`www/js/app.js` 中的 `HCApp` 类），
  通过 Capacitor 封装为 Android 原生 WebView 应用。
- **数据存储**：当前版本使用浏览器 `localStorage` 持久化数据（在 Capacitor Android
  WebView 中数据会持久保存在应用私有存储目录，随应用卸载才会清除，不会丢失）。
  这满足单机记账场景的全部需求；若后续要接入原生 SQLite，可在不改动上层业务逻辑
  的前提下，将 `HCApp.loadState / save` 中的读写替换为
  `@capacitor-community/sqlite` 插件调用（数据结构已在 `www/js/app.js` 顶部的
  `DEFAULT_TYPES / DEFAULT_PRICES` 等常量及各 `state.*` 字段中定义好，可直接映射为表结构）。
- **四个主 Tab**：今日（快速记账 + 动态步进器 + 智能累加 + 编辑）、明细（近7天矩阵 +
  筛选 + 批量操作 + CSV导出）、月报（按单价汇总 + 工资核算 + 纯CSS柱状图 + 按人员统计 +
  CSV导出）、设置（个人信息 / 单价 / 作业类型 / 工资构成 / 目标 / 主题色 / 数据备份与恢复）。
- **撤销**：内存中维护最多 30 条快照的撤销栈，支持右上角撤销操作及 `Ctrl/Cmd+Z` 快捷键。
- **每日自动备份**：每天首次操作数据时，自动把当天 `records` 与 `profile` 写入
  `localStorage` 的 `hc_backup_v1` 键，最多保留 7 天。

## 四、权限说明

`scripts/postcap.py` 会在 CI 构建时自动向 `AndroidManifest.xml` 注入以下权限：

- `INTERNET` / `ACCESS_NETWORK_STATE`：Capacitor WebView 运行及资源加载需要
- `WRITE_EXTERNAL_STORAGE` / `READ_EXTERNAL_STORAGE`（`maxSdkVersion=32`）：
  CSV / JSON 导出导入所需；Android 13+ 使用应用私有目录与分享面板，无需该权限
