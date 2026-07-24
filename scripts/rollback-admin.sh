#!/bin/bash
# 管理后台回滚脚本
# 用法: ./scripts/rollback-admin.sh [备份目录名]
# 默认回滚到最新备份，也可以指定: ./scripts/rollback-admin.sh server/public.bak.2026-07-24T19-31-21

set -e
cd "$(dirname "$0")/.."

BACKUP_DIR="${1:-$(ls -dt server/public.bak.* 2>/dev/null | head -1)}"

if [ -z "$BACKUP_DIR" ]; then
  echo "❌ 未找到备份目录"
  echo "可用备份："
  ls -d server/public.bak.* 2>/dev/null || echo "  （无）"
  exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
  echo "❌ 备份目录不存在: $BACKUP_DIR"
  exit 1
fi

echo "========== 管理后台回滚 =========="
echo "回滚源: $BACKUP_DIR"
echo ""

# 备份当前版本（以防需要再次回滚）
TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S)
ROLLBACK_FROM="server/public.bak.rollback-from-$TIMESTAMP"
mkdir -p "$ROLLBACK_FROM"
cp server/public/admin.html server/public/admin.js server/public/admin-version.json "$ROLLBACK_FROM/" 2>/dev/null || true
echo "📦 当前版本已备份到: $ROLLBACK_FROM"

# 还原
cp "$BACKUP_DIR/admin.html" server/public/admin.html
cp "$BACKUP_DIR/admin.js" server/public/admin.js
cp "$BACKUP_DIR/admin-version.json" server/public/admin-version.json 2>/dev/null || true

echo "✅ 已从 $BACKUP_DIR 还原："
echo "   - admin.html"
echo "   - admin.js"
echo "   - admin-version.json"
echo ""
echo "🔁 如果要还原刚才备份的版本："
echo "   ./scripts/rollback-admin.sh $ROLLBACK_FROM"
echo ""
echo "⚠️  注意：回滚后刷新浏览器即可生效（需清除浏览器缓存）"
