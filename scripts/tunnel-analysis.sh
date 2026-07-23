#!/bin/bash
# 隧道失效分析脚本 — 统计失效频率和模式
# 每天运行一次，输出分析报告

set -e

MONITOR_LOG="$HOME/logs/tunnel-monitor.log"
FAIL_LOG="$HOME/logs/tunnel-failures.log"

if [ ! -f "$MONITOR_LOG" ] && [ ! -f "$FAIL_LOG" ]; then
    echo "📡 隧道尚未记录，数据不足"
    exit 0
fi

TODAY=$(date '+%Y-%m-%d')
echo "=========================================="
echo "📡 隧道失效分析报告 — $TODAY"
echo "=========================================="

# 总检测次数
if [ -f "$MONITOR_LOG" ]; then
    TOTAL=$(wc -l < "$MONITOR_LOG")
    OK_COUNT=$(grep -c " OK " "$MONITOR_LOG" 2>/dev/null || echo 0)
    FAIL_COUNT=$(grep -c "FAIL\|TUNNEL_DOWN\|LOCAL_DOWN\|PID_STALE\|NO_URL" "$MONITOR_LOG" 2>/dev/null || echo 0)
    echo "总检测次数: $TOTAL"
    echo "正常次数:   $OK_COUNT"
    echo "失效次数:   $FAIL_COUNT"
    if [ "$TOTAL" -gt 0 ]; then
        RATE=$(echo "scale=2; $OK_COUNT * 100 / $TOTAL" | bc 2>/dev/null || echo "N/A")
        echo "隧道可用率:  ${RATE}%"
    fi
fi

# 今日失效
if [ -f "$FAIL_LOG" ]; then
    TODAY_FAILS=$(grep "$TODAY" "$FAIL_LOG" 2>/dev/null || echo "")
    FAIL_TOTAL=$(echo "$TODAY_FAILS" | grep -c . 2>/dev/null || echo 0)
    echo ""
    echo "今日失效次数: $FAIL_TOTAL"
    if [ "$FAIL_TOTAL" -gt 0 ]; then
        echo ""
        echo "失效时间点:"
        echo "$TODAY_FAILS" | awk '{print "  " $1, $2, $3, $4}'
    fi
fi

echo "=========================================="
