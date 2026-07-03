#!/bin/bash
# ============================================================
# Field Tracker 项目初始化脚本
# 
# 使用方法:
#   chmod +x setup.sh && ./setup.sh
#
# 前提条件:
#   - Flutter SDK (https://flutter.dev) 
#   - Node.js >= 18
#   - PostgreSQL >= 14 + PostGIS 扩展
#   - Redis >= 6
#   - 高德地图开发者 Key (https://lbs.amap.com)
# ============================================================

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
echo "============================================"
echo " Field Tracker 项目初始化"
echo "============================================"

# ---- 1. 检查环境 ----
echo ""
echo "[1/6] 检查环境..."

command -v flutter >/dev/null 2>&1 || { echo "❌ 请先安装 Flutter SDK: https://flutter.dev"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "❌ 请先安装 Node.js >= 18"; exit 1; }
command -v psql >/dev/null 2>&1 || echo "⚠️ 未检测到 psql，请确保 PostgreSQL 已安装并运行"
command -v redis-cli >/dev/null 2>&1 || echo "⚠️ 未检测到 redis-cli，请确保 Redis 已安装并运行"

echo "  Flutter: $(flutter --version 2>&1 | head -1)"
echo "  Node:    $(node --version)"
echo "  ✓ 环境检查完成"

# ---- 2. 配置高德地图 Key ----
echo ""
echo "[2/6] 配置高德地图 Key..."
AMAP_KEY_FILE="$PROJECT_ROOT/app/lib/config/amap_key.dart"

if grep -q "YOUR_AMAP_API_KEY" "$AMAP_KEY_FILE"; then
  echo "  请在 $AMAP_KEY_FILE 中替换 YOUR_AMAP_API_KEY 为你的高德地图 Key"
  echo "  申请地址: https://lbs.amap.com/dev/key/app"
  read -p "  输入你的高德地图 Key (直接回车跳过，稍后手动修改): " key
  if [ -n "$key" ]; then
    sed -i '' "s/YOUR_AMAP_API_KEY/$key/g" "$AMAP_KEY_FILE"
    echo "  ✓ Key 已配置"
  fi
else
  echo "  ✓ Key 已配置"
fi

# 同样替换 Web 管理端的高德 Key
WEB_KEY_FILE="$PROJECT_ROOT/server/public/index.html"
if grep -q "YOUR_AMAP_KEY" "$WEB_KEY_FILE"; then
  read -p "  输入高德地图 JS API Key (用于Web管理端，可复用上面那个): " web_key
  if [ -n "$web_key" ]; then
    sed -i '' "s/YOUR_AMAP_KEY/$web_key/g" "$WEB_KEY_FILE"
    echo "  ✓ Web Key 已配置"
  fi
fi

# ---- 3. 配置后端 ----
echo ""
echo "[3/6] 配置后端环境变量..."
ENV_FILE="$PROJECT_ROOT/server/.env"
if [ ! -f "$ENV_FILE" ]; then
  cp "$ENV_FILE.example" "$ENV_FILE" 2>/dev/null || true
fi
echo "  ✓ 环境变量文件: $ENV_FILE"
echo "  请根据本地数据库配置修改 DB_HOST/DB_PORT/DB_USER/DB_PASSWORD"

# ---- 4. 安装依赖 ----
echo ""
echo "[4/6] 安装后端依赖..."
cd "$PROJECT_ROOT/server"
npm install
echo "  ✓ 后端依赖安装完成"

# ---- 5. 创建 Flutter 项目 ----
echo ""
echo "[5/6] 初始化 Flutter 项目..."
FLUTTER_APP_DIR="$PROJECT_ROOT/app"

if [ ! -f "$FLUTTER_APP_DIR/pubspec.lock" ]; then
  echo "  运行 flutter create 生成平台文件..."
  cd "$PROJECT_ROOT"
  # 创建临时目录
  TMP_DIR="/tmp/flutter_init_$$"
  flutter create --org com.fieldtracker --project-name field_tracker "$TMP_DIR" >/dev/null 2>&1
  
  # 复制平台文件
  cp -r "$TMP_DIR/android/"* "$FLUTTER_APP_DIR/android/" 2>/dev/null || true
  cp -r "$TMP_DIR/ios/"* "$FLUTTER_APP_DIR/ios/" 2>/dev/null || true
  cp -r "$TMP_DIR/test/"* "$FLUTTER_APP_DIR/test/" 2>/dev/null || true
  cp "$TMP_DIR/analysis_options.yaml" "$FLUTTER_APP_DIR/" 2>/dev/null || true
  
  rm -rf "$TMP_DIR"
  echo "  ✓ Flutter 平台文件生成完成"
fi

echo "  安装 Flutter 依赖..."
cd "$FLUTTER_APP_DIR"
flutter pub get
echo "  ✓ Flutter 依赖安装完成"

# ---- 6. 初始化数据库 ----
echo ""
echo "[6/6] 初始化数据库..."
echo "  请确保 PostgreSQL 已运行且 PostGIS 扩展已安装"
read -p "  是否立即创建数据库? (y/n): " create_db

if [ "$create_db" = "y" ]; then
  # 读取数据库配置
  source "$PROJECT_ROOT/server/.env" 2>/dev/null || true
  DB_NAME="${DB_NAME:-field_tracker}"
  DB_USER="${DB_USER:-postgres}"
  
  createdb -U "$DB_USER" "$DB_NAME" 2>/dev/null || echo "  数据库已存在，跳过创建"
  psql -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_ROOT/server/src/models/database.sql"
  echo "  ✓ 数据库初始化完成"
else
  echo "  跳过数据库初始化"
  echo "  后续可手动执行: psql -U postgres -d field_tracker -f server/src/models/database.sql"
fi

echo ""
echo "============================================"
echo " 初始化完成!"
echo "============================================"
echo ""
echo "启动方式:"
echo ""
echo "  1. 启动后端:"
echo "     cd server && npm run dev"
echo ""
echo "  2. 启动 Flutter App:"
echo "     cd app && flutter run"
echo ""
echo "  3. 打开 Web 管理端:"
echo "     http://localhost:3000"
echo ""
echo "测试账号:"
echo "  管理员: 13900000001 / 123456"
echo "  员工:   13800138000 / 123456"
echo ""
echo "获取高德地图 Key:"
echo "  https://lbs.amap.com/dev/key/app"
echo "============================================"
