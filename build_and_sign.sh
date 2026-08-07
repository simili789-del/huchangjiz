#!/usr/bin/env bash
#
# build_and_sign.sh — 货场作业记账 Android App 一键构建 + 签名脚本
#
# 用法:
#   ./build_and_sign.sh                 # 用默认配置构建并签名 release APK
#   KEY_ALIAS=mykey ./build_and_sign.sh # 用自定义 key alias
#
# 前提（本机需具备其一）:
#   - Android Studio（自带 Gradle + Android SDK），或
#   - 独立安装的 Gradle 8.x + Android SDK（设置 ANDROID_HOME）
#
# 说明:
#   - 首次运行会自动用 keytool 生成一个 release.keystore（位于 keystore/，已 gitignore）
#   - 把签名信息写入 local.properties（已 gitignore，不会进版本库）
#   - 产物 APK 复制到 app/release/ 目录并打印路径
#
set -euo pipefail

# ---------- 路径 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
PROJECT_DIR="$SCRIPT_DIR"

# ---------- 可覆盖的配置（环境变量）----------
STORE_DIR="$PROJECT_DIR/keystore"
KEYSTORE="${KEYSTORE_PATH:-$STORE_DIR/release.keystore}"
KEY_ALIAS="${KEY_ALIAS:-yardrelease}"
KEY_PASS="${KEY_PASSWORD:-android}"
STORE_PASS="${STORE_PASSWORD:-android}"
KEY_VALIDITY_DAYS=10000
OUTPUT_DIR="$PROJECT_DIR/app/release"

echo "📦 货场作业记账 — 构建/签名脚本"
echo "    项目目录: $PROJECT_DIR"

# ---------- 1. 检查 Android SDK ----------
if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
  # 尝试从 local.properties 读取 sdk.dir
  if [[ -f "$PROJECT_DIR/local.properties" ]]; then
    SDK_DIR=$(grep -E "^sdk\.dir=" "$PROJECT_DIR/local.properties" | cut -d'=' -f2- | tr -d ' \r')
    if [[ -n "$SDK_DIR" ]]; then export ANDROID_HOME="$SDK_DIR"; fi
  fi
fi
if [[ -z "${ANDROID_HOME:-}" ]]; then
  echo "⚠️  未检测到 Android SDK（ANDROID_HOME / ANDROID_SDK_ROOT 均未设置）。"
  echo "    请先安装 Android Studio 或 Android SDK 命令行工具，并设置 ANDROID_HOME。"
  echo "    或在 local.properties 中写入: sdk.dir=/你的/sdk/路径"
  exit 1
fi
echo "    Android SDK: $ANDROID_HOME"

# ---------- 2. 选择构建命令（gradlew > gradle > 提示安装）----------
BUILD_CMD=""
if [[ -x "$PROJECT_DIR/gradlew" ]]; then
  BUILD_CMD="./gradlew"
elif command -v gradle >/dev/null 2>&1; then
  BUILD_CMD="gradle"
else
  echo "⚠️  未找到 gradlew 或 gradle 命令。"
  echo "    推荐：用 Android Studio 打开本项目后直接点 Run / Build APK；"
  echo "    或在本地安装 Gradle 8.x 后确保 'gradle' 在 PATH 中。"
  exit 1
fi
echo "    构建命令: $BUILD_CMD"

# ---------- 3. 生成 keystore（若不存在）----------
mkdir -p "$STORE_DIR"
if [[ ! -f "$KEYSTORE" ]]; then
  echo "🔑 未找到 keystore，正在生成 $KEYSTORE ..."
  if ! command -v keytool >/dev/null 2>&1; then
    echo "⚠️  未找到 keytool（JDK 自带）。请确认 JDK 已安装且在 PATH 中。"
    exit 1
  fi
  keytool -genkeypair -v \
    -keystore "$KEYSTORE" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA -keysize 2048 \
    -validity "$KEY_VALIDITY_DAYS" \
    -storepass "$STORE_PASS" \
    -keypass "$KEY_PASS" \
    -dname "CN=Yard Accounting, OU=Dev, O=Huochang, L=CN, ST=CN, C=CN"
  echo "    ✅ keystore 已生成"
else
  echo "    keystore 已存在: $KEYSTORE"
fi

# ---------- 4. 写入 local.properties（签名信息 + sdk.dir）----------
SDK_LINE="sdk.dir=${ANDROID_HOME}"
{
  echo "# 自动生成，请勿提交（已被 .gitignore 忽略）"
  echo "$SDK_LINE"
  echo "storeFile=$KEYSTORE"
  echo "storePassword=$STORE_PASS"
  echo "keyAlias=$KEY_ALIAS"
  echo "keyPassword=$KEY_PASS"
} > "$PROJECT_DIR/local.properties"
echo "    ✅ 已写入 local.properties（签名配置）"

# ---------- 5. 构建 release APK ----------
echo "🚀 开始构建 release APK ..."
$BUILD_CMD clean assembleRelease --no-daemon

# ---------- 6. 收集产物 ----------
mkdir -p "$OUTPUT_DIR"
shopt -s nullglob
APKS=("$PROJECT_DIR"/app/build/outputs/apk/release/*.apk)
shopt -u nullglob
if [[ ${#APKS[@]} -eq 0 ]]; then
  echo "❌ 未在 app/build/outputs/apk/release/ 找到 APK，构建可能失败。"
  exit 1
fi
for apk in "${APKS[@]}"; do
  cp "$apk" "$OUTPUT_DIR/"
done

echo ""
echo "✅ 构建完成！签名后的 APK："
ls -lh "$OUTPUT_DIR"/*.apk
echo ""
echo "💡 安装到已连接设备: adb install -r $OUTPUT_DIR/$(basename "${APKS[0]}")"
