# 货场作业记账（Flutter 版）

基于《货场作业记账 APK 软件开发方案》生成的 Flutter 原生工程骨架，实现方案中四大模块：
今日记账、明细查询、月报统计、设置管理，采用 Riverpod + Hive 三层架构（表现层 / 业务层 / 数据层）。

## 首次运行

本工程使用手写的 Android 原生工程目录（`android/`），未包含 iOS/Web 平台目录。建议按以下步骤补全并运行：

```bash
# 1. 安装依赖（需要本机已安装 Flutter SDK 3.22.x）
flutter pub get

# 2. 生成 Hive TypeAdapter（work_record.g.dart / salary_settings.g.dart 等）
flutter pub run build_runner build --delete-conflicting-outputs

# 3. 如需 iOS 工程，可另行执行（本骨架未提供 ios/ 目录）：
#    flutter create --platforms=ios .

# 4. 连接设备或模拟器后运行
flutter run
```

> 说明：本工程是在无网络、无 Flutter SDK 的环境中手工搭建的源码骨架，
> 尚未执行过 `flutter pub get` / `build_runner` / 实机编译验证。
> 请在本地或 CI（见 `.github/workflows/ci.yml`、`codemagic.yaml`）中完成依赖安装与代码生成后再构建。

## 目录结构

```
lib/
├── core/              # 常量、主题
├── data/              # Repository 实现（Hive 存取）
├── domain/            # Freezed/Hive 实体
├── presentation/      # 页面、Provider、Widget
└── main.dart          # 入口：初始化 Hive、注册 Adapter
```

## CI/CD

- `.github/workflows/ci.yml`：push/PR 时自动 `pub get` → 代码生成 → `analyze` → `test` → debug 构建。
- `codemagic.yaml`：Android 签名打包与 Google Play 内部测试轨道发布，密钥通过 CodeMagic
  环境变量（`KEYSTORE_PATH`、`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`）注入，
  不提交至 Git。
