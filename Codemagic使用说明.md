# Codemagic 在线出包使用说明（小白图文版）

> **目标**：用 Codemagic 替代 GitHub Actions，在线打出 `app-debug.apk`（测试用）和带你自己签名的 `app-release.apk`（可上架）。
>
> **适用前提**：你已经在 Codemagic 里把 GitHub 仓库连好了（看到"未找到配置文件"那张截图），并且仓库根目录已有 `codemagic.yaml`。

---

## 一、先搞清两个工作流

本项目的 `codemagic.yaml` 里写了两个工作流：

| 工作流 | 作用 | 要签名吗 | 会不会失败 |
|---|---|---|---|
| **Yard Debug APK** | 出 debug 测试包 | 不需要 | ✅ 不会失败，推荐先用它跑通 |
| **Yard Signed Release APK** | 出签名 release 包 | 需要 | 没上传 keystore 前会失败；上传后成功 |

> debug 包和 release 包的区别：debug 用临时调试签名，**不能上架**；release 用你自己的 keystore 签名，**可上架/正式分发**。

---

## 二、把 codemagic.yaml 推到仓库

你截图里已经提示了，仓库根目录要有这个文件。把 `codemagic.yaml` 放到项目根目录（和 `build.gradle.kts`、`README.md` 同级），然后推送到 GitHub：

```bash
git add codemagic.yaml
git commit -m "添加 Codemagic 在线构建配置"
git push
```

> Windows 用户用 Git Bash 或 Codemagic 截图里给出的命令行均可。推完后再点截图右上角的 **"检查配置文件"**，Codemagic 就能读到了。

---

## 三、先跑 debug（一定成功，推荐先跑它）

1. 在 Codemagic 仓库页面，点 **`开始构建`** 或 **`Start new build`**。
2. 选择工作流 **`Yard Debug APK`**。
3. 选分支 `main`，点开始。
4. 等 3–10 分钟（首次要下载依赖）。
5. 构建完成后，在 **Artifacts（产物）** 里下载 `app-debug.apk`。

这一步不需要任何签名配置，主要验证"Codemagic 能正常编译你的项目"。

---

## 四、再跑 release（需上传你的 keystore）

如果你想要**能上架的签名包**，需要先把 keystore 上传到 Codemagic：

### 4.1 生成 keystore
如果你还没有：

- **用 Android Studio（推荐）**：`Build → Generate Signed Bundle / APK → Create new...`
  - Key store path：选位置，文件名 `release.keystore`
  - Password / Confirm：设库密码（牢记）
  - Key alias：填 `yardrelease`
  - Key password：设密钥密码（可和库密码相同）
  - Validity：25 年
- **或用命令**（Git Bash）：
  ```bash
  keytool -genkey -v -keystore release.keystore -alias yardrelease \
          -keyalg RSA -keysize 2048 -validity 10000
  ```

### 4.2 在 Codemagic 上传 keystore
1. 在 Codemagic 左侧菜单找到 **Team（团队）→ Team integrations → Android keystore**（不同版本可能叫 "Code signing identities" / "Android code signing"）。
2. 点 **Add a keystore** 或 **上传 keystore**。
3. 选择你的 `release.keystore` 文件，填写：
   - **Keystore password**：库密码
   - **Key alias**：`yardrelease`
   - **Key password**：密钥密码
4. 给这个 keystore 起个 **Reference name（引用名）**，必须填 **`yard_keystore`**（因为 `codemagic.yaml` 里写的是这个名字）。
5. 保存。

> ⚠️ **keystore 是你的签名身份证，本地务必备份好，丢了无法更新已上架的 App**。

### 4.3 运行 release 工作流
1. 回到仓库页面，点 **`Start new build`**。
2. 选择工作流 **`Yard Signed Release APK`**。
3. 等构建完成，在 Artifacts 里下载 `app-release.apk`。

---

## 五、常见问题

**Q1：debug 工作流跑通了，release 报签名错误？**
→ 检查 Codemagic 里上传的 keystore 引用名是否**严格等于 `yard_keystore`**，以及 keystore password、key alias、key password 是否和生成时一致。

**Q2：Codemagic 提示 "未找到配置文件"？**
→ 确认 `codemagic.yaml` 已推到仓库根目录，且文件名**一字不差**（注意不是 `.yml`，是 `.yaml`）。然后点右上角的 **"检查配置文件"** 刷新。

**Q3：构建时间太长？**
→ 首次构建要下载 Gradle 和全部依赖，5–10 分钟正常。Codemagic 免费额度有每月分钟数限制，debug 包跑通后再按需跑 release。

**Q4：能和 GitHub Actions 一起用吗？**
→ 可以，二者不冲突。`codemagic.yaml` 给 Codemagic 用，`.github/workflows/build-apk.yml` 给 GitHub 用。想用哪个用哪个。

---

## 六、安全提醒

- `release.keystore` **不要提交到 GitHub**（仓库 `.gitignore` 已忽略 `keystore/` 和 `local.properties`）。
- Codemagic 上传的 keystore 仅用于云端签名，你的原文件仍要本地备份。
- 同一个 App 始终用同一个 keystore，别每次重新生成，否则已上架版本无法更新。
