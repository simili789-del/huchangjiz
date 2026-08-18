# 货场作业记账（Flutter 版）

基于《货场作业记账 APK 软件开发方案》生成的 Flutter 原生工程，实现今日记账、明细查询、月报统计、设置管理、Excel 导入、对账识别等模块。

采用 **Clean Architecture** 分层（core / data / domain / presentation）+ **Riverpod** 状态管理 + **Hive** 本地数据库。

## 最新更新（iOS 18 现代审美）

- **毛玻璃效果卡片**（`GlassmorphicCard`）：作为列表项与数据卡片的基类，使用 `BackdropFilter` + 半透明填充，圆角 16–24。
- **主题色严格遵循 iOS 18**：浅色背景 `#F2F2F7`，强调深灰 `#1C1C1E`，全部颜色通过 `ThemeData` / `ColorScheme` 全局定义，页面零硬编码颜色。
- **无障碍点击区域**：所有可交互控件最小高度 44px。
- **大圆角 + 轻阴影**：卡片、输入框、列表统一 radius 16–24，符合 iOS 18 审美。

## 架构与编码原则

| 规则 | 说明 |
|------|------|
| 类型安全 | 严禁 `dynamic`，全部使用泛型与强类型 |
| 异步处理 | 数据库 IO 全部非阻塞异步，不阻塞 UI |
| 审美一致性 | 颜色仅通过 ThemeData 定义 |
| 状态管理 | Riverpod `AsyncNotifier` 实现增删改查响应式更新 |

## 首次运行

```bash
# 1. 安装依赖（Flutter SDK >= 3.22）
flutter pub get

# 2. 生成 Hive TypeAdapter
flutter pub run build_runner build --delete-conflicting-outputs

# 3. 运行
flutter run
```

## 目录结构

```
lib/
├── core/
│   ├── constants/     # 作业类型、货场常量
│   ├── theme/         # AppTheme（iOS 18 配色）
│   ├── util/
│   └── widgets/       # GlassmorphicCard 等通用组件
├── data/
│   ├── repositories/  # Hive 实现的 Repository
│   └── serialization/
├── domain/
│   ├── entities/      # WorkRecord、AppSettings 等
│   └── models/
├── presentation/
│   ├── pages/         # 首页、历史、统计、设置、导入、对账
│   ├── providers/     # Riverpod Notifier / Provider
│   ├── widgets/       # 业务卡片（已接入毛玻璃）
│   └── root_shell.dart
└── main.dart
```

## 核心实体（WorkRecord）

- 日期、工人、车号、班次（白班/夜班）
- 作业类型 → 数量 Map（支持多类型同记录）
- 船名、货场（可选）
- `amount(unitPrices)` 自动计算总金额

## CI/CD

- `.github/workflows/ci.yml`：analyze + test + debug 构建
- `codemagic.yaml`：签名打包与内部测试轨道
