#!/bin/bash
# =============================================================================
#  一键发布脚本 — 外勤定位APP
# =============================================================================
# 用法:
#   ./scripts/release.sh v1.0.1 "更新日志内容"
#
# 功能:
#   1. 更新APP版本号
#   2. 打Git标签
#   3. 推送到GitHub（触发Actions自动构建+发布）
#
# 示例:
#   ./scripts/release.sh v1.0.1 "修复: 网关连接超时问题"
# =============================================================================

set -e

if [ $# -lt 1 ]; then
  echo "用法: $0 <版本号> [更新日志]"
  echo "示例: $0 v1.0.1 '修复: 网关连接超时问题'"
  exit 1
fi

VERSION="$1"
CHANGELOG="${2:-性能优化和Bug修复}"
APP_DIR="$(cd "$(dirname "$0")/../app" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo "  外勤定位APP — 发布 $VERSION"
echo "=========================================="
echo ""

# 1. 检查是否在dev分支
# ⚠️ 发布前建议先执行测试确保无回归：
#    flutter test 或 cd app && flutter test
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "dev" ]; then
  echo "❌ 请在 dev 分支执行发布 (当前: $BRANCH)"
  echo "   git checkout dev"
  exit 1
fi

# 2. 检查是否有未提交的修改
if [ -n "$(git status --porcelain)" ]; then
  echo "⚠️  有未提交的修改，先提交..."
  git add -A
  git commit -m "chore: 发布前提交 $VERSION"
fi

# 3. 更新APP版本号 (pubspec.yaml)
echo "📝 更新版本号到 $VERSION..."
VERSION_NUM="${VERSION#v}"  # 去掉v前缀
# 读取当前 build number 并递增
CURRENT_BUILD=$(grep '^version: ' "$APP_DIR/pubspec.yaml" | sed 's/.*+//')
NEW_BUILD=$((CURRENT_BUILD + 1))
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s/^version: .*/version: $VERSION_NUM+$NEW_BUILD/" "$APP_DIR/pubspec.yaml"
else
  sed -i "s/^version: .*/version: $VERSION_NUM+$NEW_BUILD/" "$APP_DIR/pubspec.yaml"
fi

# 4. 提交版本号变更
git add "$APP_DIR/pubspec.yaml"
git commit -m "chore: bump version to $VERSION"

# 5. 合并到main分支
echo "🔄 合并 dev → main..."
git checkout main
git merge dev --no-edit
git push origin main

# 6. 合并到test分支
echo "🔄 合并 dev → test..."
git checkout test
git merge dev --no-edit
git push origin test

# 7. 打标签 + 推送
echo "🏷️  创建标签 $VERSION..."
git checkout dev
git tag -a "$VERSION" -m "$CHANGELOG"
git push origin "$VERSION"

echo ""
echo "=========================================="
echo "  ✅ 发布完成!"
echo "=========================================="
echo ""
echo "  GitHub Actions 正在自动构建..."
echo "  查看进度: https://github.com/gkaikai/field-tracker/actions"
echo "  下载地址: https://github.com/gkaikai/field-tracker/releases"
echo ""
echo "  APP下次启动时会自动检测到 $VERSION"
echo "=========================================="
