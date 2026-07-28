#!/bin/bash
# ==========================================================
# APK同步脚本 — 构建后将APK复制到 server/public/ 目录
# 供服务端 /download-apk 路由使用（gofile CDN 兜底）
#
# 用法: bash scripts/sync-apk.sh
# 或在构建后执行: bash scripts/sync-apk.sh
# ==========================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APK_SRC="$PROJECT_DIR/app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
APK_DST="$PROJECT_DIR/server/public/app-arm64-v8a-release.apk"

if [ ! -f "$APK_SRC" ]; then
  echo "❌ APK源文件不存在: $APK_SRC"
  echo "请先执行 flutter build apk --release --split-per-abi"
  exit 1
fi

cp "$APK_SRC" "$APK_DST"
echo "✅ APK已同步到: $APK_DST"
echo "   文件大小: $(ls -lh "$APK_DST" | awk '{print $5}')"
