#!/bin/bash
# ============================================================
# Field Tracker 健康检查脚本
#
# 用途: 检查后端服务状态、进程存活、磁盘使用率、日志健康
# 用法: bash scripts/healthcheck.sh [--alert] [--verbose]
#
# 选项:
#   --alert     抛出问题时发送告警通知（通过日志触发 alert.ts）
#   --verbose   输出详细信息
# ============================================================

set -euo pipefail

# ---- 配置 ----
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HEALTH_URL="${HEALTH_URL:-http://localhost:3000/health}"
PM2_APP_NAME="${PM2_APP_NAME:-field-tracker}"
DISK_THRESHOLD="${DISK_THRESHOLD:-90}"
LOG_DIR="${PROJECT_DIR}/logs"
TIMEOUT_SEC=10

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ---- 计数 ----
PASS=0
FAIL=0
WARN=0

log_ok()    { echo -e "${GREEN}[✓]${NC} $1"; ((PASS++)); }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; ((WARN++)); }
log_fail()  { echo -e "${RED}[✗]${NC} $1"; ((FAIL++)); }

# ============================================================
#  1. HTTP 健康检查
# ============================================================
check_http() {
  echo ""
  echo "━━━━━ HTTP 健康检查 ━━━━━"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT_SEC" "$HEALTH_URL" 2>/dev/null || echo "000")

  if [ "$http_code" = "200" ]; then
    local body
    body=$(curl -s --max-time "$TIMEOUT_SEC" "$HEALTH_URL" 2>/dev/null)
    log_ok "HTTP 端点响应正常 (200)"
    [ "${VERBOSE:-0}" = "1" ] && echo "  响应内容: $body"
  else
    log_fail "HTTP 端点不可达 (HTTP $http_code)"
    return 1
  fi
}

# ============================================================
#  2. PM2 进程检查
# ============================================================
check_pm2() {
  echo ""
  echo "━━━━━ PM2 进程检查 ━━━━━"
  if ! command -v pm2 &>/dev/null; then
    log_warn "PM2 未安装，跳过进程检查"
    return 0
  fi

  local pm2_status
  pm2_status=$(pm2 show "$PM2_APP_NAME" 2>/dev/null || true)

  if echo "$pm2_status" | grep -q "online"; then
    log_ok "PM2 进程 [$PM2_APP_NAME] 运行中"
    local uptime_info
    uptime_info=$(pm2 show "$PM2_APP_NAME" 2>/dev/null | grep "uptime" | head -1 | sed 's/^[[:space:]]*//')
    local restart_count
    restart_count=$(pm2 show "$PM2_APP_NAME" 2>/dev/null | grep "restart" | head -1 | sed 's/^[[:space:]]*//')
    [ "${VERBOSE:-0}" = "1" ] && {
      echo "  $uptime_info"
      echo "  $restart_count"
    }
  elif echo "$pm2_status" | grep -q "errored"; then
    log_fail "PM2 进程 [$PM2_APP_NAME] 异常退出!"
    [ "${ALERT:-0}" = "1" ] && pm2 restart "$PM2_APP_NAME" --update-env && log_warn "  → 已自动重启"
  else
    log_fail "PM2 进程 [$PM2_APP_NAME] 未运行!"
  fi
}

# ============================================================
#  3. 磁盘使用率检查
# ============================================================
check_disk() {
  echo ""
  echo "━━━━━ 磁盘使用率检查 ━━━━━"
  local usage_percent
  usage_percent=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')

  if [ -z "$usage_percent" ]; then
    log_warn "无法获取磁盘使用率"
    return 0
  fi

  if [ "$usage_percent" -ge "$DISK_THRESHOLD" ]; then
    log_fail "磁盘使用率 ${usage_percent}% (阈值: ${DISK_THRESHOLD}%)"
    [ "${ALERT:-0}" = "1" ] && echo "  → 需要清理磁盘空间"
  elif [ "$usage_percent" -ge "$((DISK_THRESHOLD - 10))" ]; then
    log_warn "磁盘使用率 ${usage_percent}% (接近阈值)"
  else
    log_ok "磁盘使用率 ${usage_percent}%"
  fi

  if [ "${VERBOSE:-0}" = "1" ]; then
    echo ""
    echo "  ── df 详细输出 ──"
    df -h / | tail -1 | awk '{printf "  总容量: %s  已用: %s  可用: %s  使用率: %s\n", $2, $3, $4, $5}'
  fi
}

# ============================================================
#  4. 日志目录检查
# ============================================================
check_logs() {
  echo ""
  echo "━━━━━ 日志目录检查 ━━━━━"
  if [ -d "$LOG_DIR" ]; then
    local log_count
    log_count=$(find "$LOG_DIR" -name "*.log" -type f 2>/dev/null | wc -l)
    local log_size
    log_size=$(du -sh "$LOG_DIR" 2>/dev/null | awk '{print $1}')

    log_ok "日志目录存在: $LOG_DIR"
    echo "  日志文件数: $log_count 个, 总大小: $log_size"

    # 检查是否有近期错误日志
    local recent_errors
    recent_errors=$(find "$LOG_DIR" -name "error-*.log" -newer "$LOG_DIR" -type f 2>/dev/null | head -3)
    if [ -n "$recent_errors" ] && [ "${VERBOSE:-0}" = "1" ]; then
      echo "  ── 近期错误日志 ──"
      for f in $recent_errors; do
        echo "  $(basename "$f"): $(wc -l < "$f") 行"
      done
    fi
  else
    log_warn "日志目录不存在 ($LOG_DIR)"
    mkdir -p "$LOG_DIR"
    log_warn "  已创建日志目录"
  fi

  # 检查日志轮转是否正常
  local archive_count
  archive_count=$(find "$LOG_DIR" -name "*.gz" -type f 2>/dev/null | wc -l)
  [ "$archive_count" -gt 0 ] && echo "  归档日志: $archive_count 个"
}

# ============================================================
#  5. 内存使用检查
# ============================================================
check_memory() {
  echo ""
  echo "━━━━━ 内存使用检查 ━━━━━"
  if command -v pm2 &>/dev/null; then
    local mem_info
    mem_info=$(pm2 show "$PM2_APP_NAME" 2>/dev/null | grep "memory" | head -1 || true)
    if [ -n "$mem_info" ]; then
      log_ok "PM2 进程内存: $(echo "$mem_info" | sed 's/^[[:space:]]*//')"
    fi
  fi

  # 系统内存概览
  if [ "${VERBOSE:-0}" = "1" ]; then
    echo ""
    echo "  ── 系统内存 ──"
    vm_stat 2>/dev/null | head -10 || free -h 2>/dev/null || true
  fi
}

# ============================================================
#  6. 数据库连通性检查
# ============================================================
check_database() {
  echo ""
  echo "━━━━━ 数据库连接检查 ━━━━━"
  # 简单的 TCP 端口检查
  local pg_host="${PGHOST:-localhost}"
  local pg_port="${PGPORT:-5432}"
  local redis_host="${REDIS_HOST:-localhost}"
  local redis_port="${REDIS_PORT:-6379}"

  # PostgreSQL
  if command -v nc &>/dev/null; then
    if nc -z -w3 "$pg_host" "$pg_port" 2>/dev/null; then
      log_ok "PostgreSQL ($pg_host:$pg_port) 可达"
    else
      log_fail "PostgreSQL ($pg_host:$pg_port) 不可达"
    fi

    # Redis
    if nc -z -w3 "$redis_host" "$redis_port" 2>/dev/null; then
      log_ok "Redis ($redis_host:$redis_port) 可达"
    else
      log_warn "Redis ($redis_host:$redis_port) 不可达 (非致命)"
    fi
  else
    log_warn "nc 未安装，跳过端口连通性检查"
  fi
}

# ============================================================
#  主流程
# ============================================================
main() {
  echo "╔══════════════════════════════════════════════╗"
  echo "║      Field Tracker 健康检查                   ║"
  echo "║      $(date '+%Y-%m-%d %H:%M:%S')               ║"
  echo "╚══════════════════════════════════════════════╝"
  echo "项目路径: $PROJECT_DIR"

  check_http
  check_pm2
  check_disk
  check_logs
  check_memory
  check_database

  # ---- 结语 ----
  echo ""
  echo "╔══════════════════════════════════════════════╗"

  local total=$((PASS + FAIL + WARN))
  if [ "$FAIL" -gt 0 ]; then
    echo "║  ${RED}结果: $PASS ✓  $WARN !  $FAIL ✗  (共 $total 项)${NC}   ║"
    exit 1
  elif [ "$WARN" -gt 0 ]; then
    echo "║  ${YELLOW}结果: $PASS ✓  $WARN !  $FAIL ✗  (共 $total 项)${NC}   ║"
    exit 0
  else
    echo "║  ${GREEN}结果: $PASS ✓  $WARN !  $FAIL ✗  (共 $total 项)${NC}   ║"
    exit 0
  fi
  echo "╚══════════════════════════════════════════════╝"
}

# ---- 参数解析 ----
ALERT=0
VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --alert) ALERT=1 ;;
    --verbose) VERBOSE=1 ;;
  esac
done

main
