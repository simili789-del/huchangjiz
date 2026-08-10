#!/usr/bin/env python3
"""
在 CodeMagic CI 中，执行 `npx cap add android` / `npx cap sync android` 之后运行。
职责：
1. 向 AndroidManifest.xml 追加所需权限（若尚未存在）
2. 确保 MainActivity 重写 onResume（Capacitor BridgeActivity 已默认处理，做兼容性检查）
3. 向 android/app/build.gradle 注入 release 签名配置（读取 CodeMagic 注入的
   CM_KEYSTORE_PATH / CM_KEYSTORE_PASSWORD / CM_KEY_ALIAS / CM_KEY_PASSWORD 环境变量）
该脚本可安全重复执行（幂等）。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANDROID_DIR = os.path.join(ROOT, 'android')
MANIFEST_PATH = os.path.join(ANDROID_DIR, 'app', 'src', 'main', 'AndroidManifest.xml')
BUILD_GRADLE_PATH = os.path.join(ANDROID_DIR, 'app', 'build.gradle')

REQUIRED_PERMISSIONS = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.WRITE_EXTERNAL_STORAGE',
    'android.permission.READ_EXTERNAL_STORAGE',
]


def patch_manifest():
    if not os.path.exists(MANIFEST_PATH):
        print(f'[postcap] 警告：未找到 {MANIFEST_PATH}，跳过权限注入')
        return
    with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    added = []
    for perm in REQUIRED_PERMISSIONS:
        tag = f'<uses-permission android:name="{perm}" />'
        if perm not in content:
            added.append(tag)

    if added:
        insertion = '\n    ' + '\n    '.join(added)
        # 插入到 <manifest ...> 开始标签之后
        content = re.sub(r'(<manifest[^>]*>)', r'\1' + insertion, content, count=1)
        # WRITE_EXTERNAL_STORAGE 需要 maxSdkVersion 兼容新系统的分区存储策略
        content = content.replace(
            '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />',
            '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="32" />',
        )
        with open(MANIFEST_PATH, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f'[postcap] 已向 AndroidManifest.xml 添加 {len(added)} 项权限')
    else:
        print('[postcap] AndroidManifest.xml 权限已齐全，无需修改')


def patch_build_gradle():
    if not os.path.exists(BUILD_GRADLE_PATH):
        print(f'[postcap] 警告：未找到 {BUILD_GRADLE_PATH}，跳过签名配置注入')
        return
    with open(BUILD_GRADLE_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1) 注入 signingConfigs 块（如缺失）
    if 'signingConfigs' not in content:
        signing_block = '''    signingConfigs {
        release {
            if (System.getenv("CM_KEYSTORE_PATH")) {
                storeFile file(System.getenv("CM_KEYSTORE_PATH"))
                storePassword System.getenv("CM_KEYSTORE_PASSWORD")
                keyAlias System.getenv("CM_KEY_ALIAS")
                keyPassword System.getenv("CM_KEY_PASSWORD")
            }
        }
    }
'''

        if 'buildTypes {' in content:
            content = content.replace('buildTypes {', signing_block + '    buildTypes {', 1)
        else:
            print('[postcap] 警告：未在 build.gradle 中找到 buildTypes 块，跳过 signingConfigs 注入')
            return

    # 2) 在 buildTypes 内的 release 块中追加 signingConfig 引用（仅当尚未设置）
    #    注意：必须插到 buildTypes.release 里，而不是 signingConfigs.release（后者是配置
    #    定义块，里面写 signingConfig 属于非法 DSL，会让 Gradle 配置阶段直接报错）。
    if 'signingConfig signingConfigs.release' not in content:
        bt_idx = content.find('buildTypes {')
        if bt_idx == -1:
            print('[postcap] 警告：未找到 buildTypes 块，跳过 signingConfig 引用注入')
        else:
            rest = content[bt_idx:]
            m = re.search(r'release\s*\{', rest)
            if m:
                ins = bt_idx + m.end()
                content = content[:ins] + '\n            signingConfig signingConfigs.release' + content[ins:]
            else:
                print('[postcap] 警告：未在 buildTypes 中找到 release 块')

    with open(BUILD_GRADLE_PATH, 'w', encoding='utf-8') as f:
        f.write(content)
    print('[postcap] 已向 build.gradle 注入 release 签名配置')


def main():
    if not os.path.isdir(ANDROID_DIR):
        print('[postcap] 错误：android/ 目录不存在，请先执行 `npx cap add android`', file=sys.stderr)
        sys.exit(1)
    patch_manifest()
    patch_build_gradle()
    print('[postcap] 完成')


if __name__ == '__main__':
    main()
