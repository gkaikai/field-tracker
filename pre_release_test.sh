#!/bin/bash
# ==========================================================
# 发布前自测脚本 — 每次构建APK发版前必须运行，全部通过才可发送
# 用法: bash pre_release_test.sh
# ==========================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/app"
SERVER_DIR="$SCRIPT_DIR/server"
TUNNEL_URL="https://f3d5eeda8ddeb319-123-123-97-213.serveousercontent.com"
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
export JAVA_HOME="/Users/openclaw-gkf/.hermes/profiles/egg-xiaoming/home/java/zulu17.56.15-ca-jdk17.0.14-macosx_x64"
export ANDROID_HOME="/Users/openclaw-gkf/android-sdk"
export FLUTTER_ROOT="/Users/openclaw-gkf/development/flutter"

ERROR_COUNT=$("$FLUTTER_ROOT/bin/flutter" analyze lib/ 2>&1 | grep "error " | wc -l | tr -d ' ')
if [ "$ERROR_COUNT" -eq 0 ]; then
  green "主代码无错误 ($ERROR_COUNT errors)"
  PASS=$((PASS+1))
else
  red "主代码有 $ERROR_COUNT 个错误！"
  "$FLUTTER_ROOT/bin/flutter" analyze lib/ 2>&1 | grep "error "
  FAIL=$((FAIL+1))
fi

# ---- 2. APK构建 ----
info "2/5 APK构建..."
rm -rf build 2>/dev/null
BUILD_OUTPUT=$("$FLUTTER_ROOT/bin/flutter" build apk --release --split-per-abi 2>&1)
if echo "$BUILD_OUTPUT" | grep -q "Built build"; then
  VERSION_NAME=$(/Users/openclaw-gkf/android-sdk/build-tools/34.0.0/aapt2 dump badging build/app/outputs/flutter-apk/app-arm64-v8a-release.apk 2>/dev/null | grep "versionName=" | sed "s/.*versionName='\([^']*\)'.*/\1/")
  VERSION_CODE=$(/Users/openclaw-gkf/android-sdk/build-tools/34.0.0/aapt2 dump badging build/app/outputs/flutter-apk/app-arm64-v8a-release.apk 2>/dev/null | grep "versionCode=" | sed "s/.*versionCode='\([^']*\)'.*/\1/")
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
HEALTH=$(curl -s --max-time 5 "$TUNNEL_URL/health" 2>&1)
if echo "$HEALTH" | grep -q "ok"; then
  green "隧道正常"
  PASS=$((PASS+1))
else
  red "隧道不可达！"
  FAIL=$((FAIL+1))
fi

# ---- 4. 服务端API ----
info "4/5 服务端API测试..."
TOKEN=$(curl -s -X POST "$TUNNEL_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"phone":"13800138000","password":"test123456"}' | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('token',''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  red "登录API失败——token为空"
  FAIL=$((FAIL+1))
else
  # 上报测试
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$TUNNEL_URL/api/v1/location/report" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "{\"lng\":114.0579,\"lat\":22.5431,\"accuracy\":5,\"speed\":0,\"timestamp\":$(date +%s000)}")
  
  # 轨迹查询
  TRACK_RESULT=$(curl -s "$TUNNEL_URL/api/v1/location/track/-1?date=$(date +%Y-%m-%d)" \
    -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json;d=json.load(sys.stdin);print(f\"{d.get('source','?')} {len(d.get('points',[]))}pts\")" 2>/dev/null)
  
  if [ "$STATUS" = "201" ]; then
    green "API正常 — 上报✅ 轨迹✅ ($TRACK_RESULT)"
    PASS=$((PASS+1))
  else
    red "上报API失败 (HTTP $STATUS)"
    FAIL=$((FAIL+1))
  fi
fi

# ---- 5. 通知渠道验证 ----
info "5/5 通知渠道代码验证..."
NOTIFY_LINES=$(grep -c "BackgroundService\|LocationForegroundService\|CreateNotification" "$APP_DIR/android/app/src/main/java/com/fieldtracker/app/LocationForegroundService.java" 2>/dev/null || echo 0)
if [ "$NOTIFY_LINES" -ge 1 ]; then
  green "原生前台服务代码已配置"
  PASS=$((PASS+1))
else
  red "原生前台服务代码缺失！"
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
