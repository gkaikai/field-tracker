#!/bin/bash
# 隧道生命周期监测 — 每次运行记录隧道年龄
# 配合cron每5分钟执行

set -e

LIFECYCLE_LOG="$HOME/logs/tunnel-lifecycle.log"
TUNNEL_URL_FILE="/tmp/fieldtracker-tunnel-url.txt"
PID_FILE="/tmp/fieldtracker-tunnel.pid"

mkdir -p "$HOME/logs"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TUNNEL_URL=$(cat "$TUNNEL_URL_FILE" 2>/dev/null || echo "")

# 检查隧道进程是否存在
PID=""
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ! kill -0 "$PID" 2>/dev/null; then
        PID=""
    fi
fi

# 检查旧隧道是否还活着
if [ -f "$LIFECYCLE_LOG" ]; then
    LAST_ENTRY=$(tail -1 "$LIFECYCLE_LOG")
    LAST_URL=$(echo "$LAST_ENTRY" | awk '{print $4}')
    LAST_STATUS=$(echo "$LAST_ENTRY" | awk '{print $3}')
fi

if [ -n "$PID" ] && [ -n "$TUNNEL_URL" ]; then
    # 隧道活着 → lifecylce已由keepalive脚本记录，这里只记录变化事件
    if [ "$LAST_URL" != "$TUNNEL_URL" ] || [ "$LAST_STATUS" = "DOWN" ]; then
        echo "$TIMESTAMP ACTIVE $TUNNEL_URL" >> "$LIFECYCLE_LOG"
    fi
else
    # 隧道死了 → 记录死亡
    # 从上次的日志提取最后一条ALIVE记录来算寿命
    if [ -n "$LAST_URL" ] && [ "$LAST_STATUS" = "ALIVE" ]; then
        DEATH_EPOCH=$(date +%s)
        # 找这条隧道的出生时间
        BIRTH_LINE=$(grep "BIRTH $LAST_URL" "$LIFECYCLE_LOG" 2>/dev/null | tail -1)
        if [ -n "$BIRTH_LINE" ]; then
            BIRTH_TIME=$(echo "$BIRTH_LINE" | awk '{print $1, $2}')
            BIRTH_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$BIRTH_TIME" +%s 2>/dev/null)
            LIFETIME=$(( (DEATH_EPOCH - BIRTH_EPOCH) / 60 ))
            echo "$TIMESTAMP DEATH $LAST_URL lifetime=${LIFETIME}min" >> "$LIFECYCLE_LOG"
        else
            echo "$TIMESTAMP DEATH $LAST_URL lifetime=unknown" >> "$LIFECYCLE_LOG"
        fi
    fi
    echo "$TIMESTAMP DOWN (无隧道)" >> "$LIFECYCLE_LOG"
fi
