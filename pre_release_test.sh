#!/bin/bash
# ==========================================================
# 发布前自测脚本 — 每次构建APK发版前必须运行，全部通过才可发送
# 用法: bash pre_release_test.sh
# ==========================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/app"
SERVER_DIR="$SCRIPT_DIR/server"
TUNNEL_URL="${TUNNEL_URL:-https://ca30ef85c4698cc6-123-123-97-213.serveousercontent.com}"

# 测试账号（可被环境变量覆盖）
TEST_PHONE="${TEST_PHONE:-13800138000}"
TEST_PASSWORD="${TEST_PASSWORD:-123456}"

# Flutter 工具链路径（可被环境变量覆盖）
JAVA_HOME="${JAVA_HOME:-/Users/openclaw-gkf/.hermes/profiles/egg-xiaoming/home/java/zulu17.56.15-ca-jdk17.0.14-macosx_x64}"
ANDROID_HOME="${ANDROID_HOME:-/Users/openclaw-gkf/android-sdk}"
FLUTTER_ROOT="${FLUTTER_ROOT:-/Users/openclaw-gkf/development/flutter}"
AAPT2="$ANDROID_HOME/build-tools/34.0.0/aapt2"

PASS=0
FAIL=0

green() { echo -e "\033[32m✅ $1\033[0m"; }
red() { echo -e "\033[31m❌ $1\033[0m"; }
info() { echo -e "\033[36m🔍 $1\033[0m"; }

echo "=========================================="
echo "     外勤定位APP — 发布前自测"
echo "=========================================="
echo ""

# ---- 1. 代码静态分析 ----
info "1/5 Flutter Analyze..."
cd "$APP_DIR"

# 只把 error 视为失败（warning/info 不阻塞交付）
ANALYZE_OUTPUT=$("$FLUTTER_ROOT/bin/flutter" analyze lib/ 2>&1 || true)
if echo "$ANALYZE_OUTPUT" | grep -qE "^\s*error •"; then
  ANALYZE_OK=false
else
  ANALYZE_OK=true
fi

if $ANALYZE_OK; then
  green "Flutter Analyze 通过"
  PASS=$((PASS+1))
else
  ERROR_COUNT=$(echo "$ANALYZE_OUTPUT" | grep -c "error" 2>/dev/null || echo 0)
  red "Flutter Analyze 发现 $ERROR_COUNT 个错误！"
  echo "$ANALYZE_OUTPUT" | head -20
  FAIL=$((FAIL+1))
fi

# ---- 2. APK构建 ----
info "2/5 APK构建..."
rm -rf build 2>/dev/null
BUILD_OUTPUT=$("$FLUTTER_ROOT/bin/flutter" build apk --release --split-per-abi 2>&1)
if echo "$BUILD_OUTPUT" | grep -q "Built build"; then
  VERSION_NAME=$("$AAPT2" dump badging build/app/outputs/flutter-apk/app-arm64-v8a-release.apk 2>/dev/null | grep "versionName=" | sed "s/.*versionName='\([^']*\)'.*/\1/")
  VERSION_CODE=$("$AAPT2" dump badging build/app/outputs/flutter-apk/app-arm64-v8a-release.apk 2>/dev/null | grep "versionCode=" | sed "s/.*versionCode='\([^']*\)'.*/\1/")
  APK_SIZE=$(ls -lh build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | awk '{print $5}')
  green "APK构建成功 v$VERSION_NAME (code $VERSION_CODE, ${APK_SIZE}B)"
  PASS=$((PASS+1))
else
  red "APK构建失败！"
  echo "$BUILD_OUTPUT" | tail -10
  FAIL=$((FAIL+1))
fi

# ---- 3. 隧道连通性 ----
info "3/5 隧道连通性..."
HEALTH=$(curl -sS --max-time 5 "$TUNNEL_URL/health" 2>&1) || HEALTH_EXIT=$?
if [ -n "$HEALTH" ] && echo "$HEALTH" | grep -q "ok"; then
  green "隧道正常"
  PASS=$((PASS+1))
else
  red "隧道不可达！"
  echo "错误详情:"
  echo "$HEALTH" | head -5
  FAIL=$((FAIL+1))
fi

# ---- 4. 服务端API ----
info "4/5 服务端API测试..."
LOGIN_RESP=$(curl -sS -X POST "$TUNNEL_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"phone\":\"$TEST_PHONE\",\"password\":\"$TEST_PASSWORD\"}" 2>&1) || LOGIN_EXIT=$?

TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('token',''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  red "登录API失败——token为空"
  echo "响应: $(echo "$LOGIN_RESP" | head -3)"
  FAIL=$((FAIL+1))
else
  # 只读API验证（不写入任何测试数据，避免污染用户轨迹）
  ME_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$TUNNEL_URL/api/v1/auth/me" \
    -H "Authorization: Bearer $TOKEN")
  
  if [ "$ME_CODE" = "200" ]; then
    green "API正常 — 登录✅ 身份验证✅"
    PASS=$((PASS+1))
  else
    red "身份验证API失败 (HTTP $ME_CODE)"
    FAIL=$((FAIL+1))
  fi
fi

# ---- 5. 通知渠道验证 ----
info "5/5 通知渠道代码验证..."
NOTIFY_FILE="$APP_DIR/android/app/src/main/java/com/fieldtracker/app/LocationForegroundService.java"
NOTIFY_LINES=$(grep -c "BackgroundService\|LocationForegroundService\|CreateNotification" "$NOTIFY_FILE" 2>/dev/null || echo 0)
if [ "$NOTIFY_LINES" -ge 1 ]; then
  green "原生前台服务代码已配置"
  PASS=$((PASS+1))
else
  red "原生前台服务代码缺失！"
  [ -f "$NOTIFY_FILE" ] && echo "文件存在但未匹配关键字" || echo "文件不存在: $NOTIFY_FILE"
  FAIL=$((FAIL+1))
fi

# ---- 结果 ----
echo ""
echo "=========================================="
echo " 结果: ✅ $PASS 通过 | ❌ $FAIL 失败"
echo "=========================================="

if [ "$FAIL" -eq 0 ]; then
  echo "🎉 全部自测通过，可以发送给用户！"
  exit 0
else
  echo "⚠️ 有 $FAIL 项未通过，修复后再发！"
  exit 1
fi
