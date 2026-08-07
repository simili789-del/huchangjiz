#!/usr/bin/env bash
#
# push_to_github.sh — 把本仓库推送到 GitHub（需在本机联网环境运行）
#
# 前置条件:
#   1) 已安装 gh 并登录:        gh auth login
#   2) 已配置 git 身份:        git config --global user.name  "你的名字"
#                              git config --global user.email "you@example.com"
#   3) 能访问 github.com（本沙箱网络受限，需在本地电脑运行）
#
# 用法:
#   ./push_to_github.sh                       # 创建私有仓库并推送
#   REPO_VISIBILITY=public ./push_to_github.sh
#   REPO_NAME=my-yard-app ./push_to_github.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPO_NAME="${REPO_NAME:-yard-accounting-android}"
REPO_VIS="${REPO_VISIBILITY:-private}"
REMOTE="${REMOTE:-origin}"

echo "🚀 准备推送到 GitHub ..."
echo "    仓库名: $REPO_NAME"
echo "    可见性: $REPO_VIS"

# 1) 检查 gh 登录
if ! gh auth status >/dev/null 2>&1; then
  echo "⚠️  未登录 GitHub。请先运行: gh auth login"
  exit 1
fi

# 2) git 身份
if [[ -z "$(git config user.name)" || -z "$(git config user.email)" ]]; then
  echo "⚠️  未配置 git 身份，请先运行:"
  echo "    git config --global user.name  \"你的名字\""
  echo "    git config --global user.email \"you@example.com\""
  exit 1
fi

# 3) 初始化（若尚未）
if [[ ! -d .git ]]; then
  git init -q
  git branch -M main
fi

# 4) 提交最新改动
git add -A
if git diff --cached --quiet; then
  echo "    （无新改动需要提交）"
else
  git commit -q -m "chore: 一键构建/签名脚本与发布配置" || true
fi

# 5) 创建远程仓库（若不存在）
if ! gh repo view "$REPO_NAME" >/dev/null 2>&1; then
  echo "📦 在 GitHub 创建仓库 $REPO_NAME ($REPO_VIS) ..."
  gh repo create "$REPO_NAME" --"$REPO_VIS" --source=. --remote="$REMOTE" --push
else
  echo "   仓库已存在，直接推送。"
  if ! git remote | grep -q "^$REMOTE$"; then
    gh repo set-default "$REPO_NAME" 2>/dev/null || true
    git remote add "$REMOTE" "https://github.com/$(gh api user --jq .login)/$REPO_NAME.git"
  fi
  git push -u "$REMOTE" main
fi

echo ""
echo "✅ 完成！仓库地址: $(gh repo view "$REPO_NAME" --json url -q .url)"
