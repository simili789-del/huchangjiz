# 本地 Flutter 环境搭建（沙箱 / CI 等价验证用）

> 目的：在本地沙箱里装一套**与 CI（CodeMagic `android-workflow`）等价**的 Flutter 环境，
> 让 `flutter analyze` / `flutter pub get` / `flutter build` 能本地自验，不再靠贴 CI 日志来回跑。

---

## 0. 背景：为什么要手动装

- 系统预装的 Flutter 在 `/opt/flutter`，版本 **3.0.0 / Dart 2.17.0**（2022 年的旧版）。
- 本项目 `pubspec` 要求 **Dart SDK `>=3.7.2 <4.0.0`**，旧版 `pub get` 直接失败。
- CI 的 `Analyze code` 步骤 = `flutter analyze` 静态检查，本地没新版就验不了。

**结论**：必须装一个 3.x 尾巴版本（Dart 3.7+/3.8），且 `<4.0.0`（否则违反约束）。

---

## 1. 网络约束（沙箱实测）

| 地址 | 状态 | 说明 |
|---|---|---|
| `storage.googleapis.com` | ❌ 被墙 | Flutter 官方存储（引擎/Dart SDK 都在这） |
| `github.com`（直连） | ❌ 被墙 | `flutter upgrade` 的 git fetch 走这 |
| `gh-proxy.com` | ✅ 通 | 代理 github，git 操作可用 |
| `pub.dev` | ✅ 通 | pub 包默认源 |
| `storage.flutter-io.cn` | ✅ 通但**极慢（~0.13 MB/s）** | 国内镜像，但带宽烂，1.4G 要 3 小时 |
| `mirrors.cloud.tencent.com/flutter` | ✅ 通且**快（~14 MB/s）** | ✅ 实际使用的镜像 |

> ⚠️ `flutter-io.cn` 的 `releases` JSON 是**过期缓存**（只到 3.3.3），但其 tarball 实际有现代版本。
> 所以**不能**用 `flutter upgrade`（它信那份旧 JSON），必须手动下 tarball。

---

## 2. 安装步骤（一次性的，装完持久保留）

### 2.1 下载 Flutter 3.32.4（腾讯云镜像，约 1.4G，1~2 分钟）

```bash
curl -s -o /tmp/flutter.tar.xz \
  "https://mirrors.cloud.tencent.com/flutter/flutter_infra_release/releases/stable/linux/flutter_linux_3.32.4-stable.tar.xz"
```

> 选 3.32.4 的原因：自带 **Dart 3.8.1**，满足 `>=3.7.2 <4.0.0`。
> 不要用 4.x（违反 `<4.0.0`），也不要用 `flutter-io.cn`（太慢/JSON 过期）。

### 2.2 解压到独立目录（不动系统旧的 `/opt/flutter`）

```bash
rm -rf /opt/flutter332 && mkdir -p /opt/flutter332
tar -xf /tmp/flutter.tar.xz -C /opt/flutter332
# 解压后得到 /opt/flutter332/flutter
```

### 2.3 修 Flutter 自带 git remote（版本检查要走代理）

Flutter 首次运行会 `git fetch` 上游 tags，直连 github 被墙。把 remote 改指 gh-proxy：

```bash
cd /opt/flutter332/flutter
git remote set-url origin "https://gh-proxy.com/https://github.com/flutter/flutter.git"
```

### 2.4 写 wrapper，让 `flutter`/`dart` 自动指向新版并自带镜像环境变量

放在 `/usr/local/bin`（在 PATH 中排在原 `/opt/flutter/bin` 之前，自动覆盖）。

`/usr/local/bin/flutter`：
```sh
#!/bin/sh
export FLUTTER_STORAGE_BASE_URL=https://mirrors.cloud.tencent.com/flutter
export PUB_HOSTED_URL=https://mirrors.cloud.tencent.com/dart-pub
exec /opt/flutter332/flutter/bin/flutter "$@"
```

`/usr/local/bin/dart`：
```sh
#!/bin/sh
export PUB_HOSTED_URL=https://mirrors.cloud.tencent.com/dart-pub
exec /opt/flutter332/flutter/bin/dart "$@"
```

```bash
chmod +x /usr/local/bin/flutter /usr/local/bin/dart
```

---

## 3. 使用（每个新会话直接敲，无需设环境变量）

```bash
cd /workspace/yard_accounting

# 取依赖（首次较慢，约 15 分钟，依赖树大且顺带解析 example 目录）
flutter pub get

# 生成代码（.g.dart / Hive Adapter / freezed）—— CI 也会先跑这步
flutter pub run build_runner build --delete-conflicting-outputs

# 静态检查（等价于 CI 的 Analyze code 步骤）
flutter analyze
```

> 注意：`flutter analyze` 之前**必须先 build_runner**，否则会报
> `uri_has_not_been_generated` / `undefined_function`（那是缺生成文件，不是真 lint 错误）。

---

## 4. 验证是否生效

全新 shell（不手动 export 任何变量）下：

```bash
which flutter          # -> /usr/local/bin/flutter
flutter --version      # -> Flutter 3.32.4 / Dart 3.8.1
flutter analyze        # -> No issues found!
```

---

## 5. 环境重置后如何恢复

若沙箱被整体销毁（非普通新会话），`/opt/flutter332` 会丢失，按本文 **第 2 节** 重跑即可。
第 3、4 节的使用方式不变。

---

## 6. 当前状态（2026-08-14）

- 已修复并推送的 lint 提交：`4d40f99`、`743374b`（共 6 条 analyze 问题，本地已验证清零）。
- 本地 `flutter analyze` 结果：**No issues found!**
- 触发 CI 验证：CodeMagic → `android-workflow` → **Start new build**（勿用 Rerun）。
