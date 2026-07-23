#!/bin/bash
# field_tracker 隧道保活脚本 v2 (升级版)
# 每5分钟检查一次，隧道断开自动重连
# 当隧道URL变更时，POST上报到服务端API，APK端自动轮询获取新URL
#
# 分析日志写入: ~/logs/tunnel-monitor.log (OK/FAIL + URL)
# 失效分析日志:  ~/logs/tunnel-failures.log

set -e

TUNNEL_PID_FILE="/tmp/fieldtracker-tunnel.pid"
TUNNEL_URL_FILE="/tmp/fieldtracker-tunnel-url.txt"
TUNNEL_RAW_LOG="/tmp/fieldtracker-tunnel-raw.log"
MONITOR_LOG="$HOME/logs/tunnel-monitor.log"
LIFECYCLE_LOG="$HOME/logs/tunnel-lifecycle.log"
FAIL_LOG="$HOME/logs/tunnel-failures.log"
PORT=3000
API_BASE="http://localhost:$PORT"
PREEMPTIVE_AGE_THRESHOLD_MIN=720  # 12小时后提前生成备用隧道

mkdir -p "$HOME/logs"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ── 辅助函数：上报隧道URL到API ──
report_url() {
    local url="$1"
    if [ -n "$url" ]; then
        # 记录到文件
        echo "$url" > "$TUNNEL_URL_FILE"
        # POST到API
        curl -sf -X POST "$API_BASE/api/v1/tunnel" \
            -H "Content-Type: application/json" \
            -d "{\"url\":\"$url\"}" > /dev/null 2>&1 && \
        echo "$TIMESTAMP NEW_URL $url" >> "$MONITOR_LOG" || \
        echo "$TIMESTAMP REPORT_FAIL $url" >> "$MONITOR_LOG"
    fi
}

# ── 辅助函数：获取最新URL ──
get_url() {
    if [ -f "$TUNNEL_URL_FILE" ]; then
        cat "$TUNNEL_URL_FILE"
    fi
}

# ── 1. 检查现有隧道是否存活 ──
OLD_URL=$(get_url)
if [ -f "$TUNNEL_PID_FILE" ]; then
    OLD_PID=$(cat "$TUNNEL_PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        # 进程在运行，检查本地端口和隧道可达性
        if curl -sf "http://localhost:$PORT/health" > /dev/null 2>&1; then
            if [ -n "$OLD_URL" ] && curl -sf --max-time 5 "$OLD_URL/api/v1/tunnel/health" > /dev/null 2>&1; then
                # 一切正常 → 记录生命周期+年龄
                START_EPOCH=$(stat -f "%m" "$TUNNEL_URL_FILE" 2>/dev/null || echo 0)
                NOW_EPOCH=$(date +%s)
                AGE=$(( (NOW_EPOCH - START_EPOCH) / 60 ))
                echo "$TIMESTAMP ALIVE $OLD_URL age=${AGE}min" >> "$LIFECYCLE_LOG"
                echo "$TIMESTAMP OK $OLD_URL" >> "$MONITOR_LOG"
                
                # ── 4. 隧道已运行超过阈值 → 提前生成备用隧道 ──
                if [ "$AGE" -ge "$PREEMPTIVE_AGE_THRESHOLD_MIN" ]; then
                    # 检查是否已有备用隧道
                    BACKUP_URL=$(curl -sf "$API_BASE/api/v1/tunnel" 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get('backup_url',''))" 2>/dev/null)
                    if [ -z "$BACKUP_URL" ] || ! curl -sf --max-time 5 "$BACKUP_URL/api/v1/tunnel/health" > /dev/null 2>&1; then
                        echo "$TIMESTAMP PREEMPTIVE — 生成备用隧道..." >> "$MONITOR_LOG"
                        # 建立第二个隧道（不同端口的转发，用另一个ssh连接）
                        nohup ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                            -o ExitOnForwardFailure=yes \
                            -o StrictHostKeyChecking=no \
                            -R 80:localhost:$PORT serveo.net 2>/tmp/fieldtracker-backup-raw.log &
                        BACKUP_PID=$!
                        sleep 6
                        NEW_BACKUP_URL=$(grep -o 'https://[a-z0-9-]*\.serveousercontent\.com' /tmp/fieldtracker-backup-raw.log 2>/dev/null | head -1)
                        # 重试最多3次，等待serveo生成URL
                        RETRIES=0
                        while [ -z "$NEW_BACKUP_URL" ] && [ $RETRIES -lt 3 ]; do
                            sleep 5
                            RETRIES=$((RETRIES + 1))
                            NEW_BACKUP_URL=$(grep -o 'https://[a-z0-9-]*\.serveousercontent\.com' /tmp/fieldtracker-backup-raw.log 2>/dev/null | head -1)
                        done
                        if [ -n "$NEW_BACKUP_URL" ]; then
                            # 上报备用隧道到API
                            curl -sf -X POST "$API_BASE/api/v1/tunnel/backup" \
                                -H "Content-Type: application/json" \
                                -d "{\"url\":\"$NEW_BACKUP_URL\"}" > /dev/null 2>&1
                            echo "$BACKUP_PID" > /tmp/fieldtracker-backup.pid
                            echo "$TIMESTAMP BACKUP_CREATED $NEW_BACKUP_URL PID=$BACKUP_PID" >> "$MONITOR_LOG"
                        fi
                    fi
                fi
                exit 0
            else
                echo "$TIMESTAMP TUNNEL_DOWN $OLD_URL" >> "$FAIL_LOG"
                echo "$TIMESTAMP TUNNEL_DOWN $OLD_URL — 隧道不可达，重建" >> "$MONITOR_LOG"
            fi
        else
            echo "$TIMESTAMP LOCAL_DOWN" >> "$FAIL_LOG"
            echo "$TIMESTAMP LOCAL_DOWN — 本地服务不可达" >> "$MONITOR_LOG"
        fi
    else
        echo "$TIMESTAMP PID_STALE $OLD_PID" >> "$FAIL_LOG"
        echo "$TIMESTAMP PID_STALE $OLD_PID — 进程已死" >> "$MONITOR_LOG"
    fi
    kill "$OLD_PID" 2>/dev/null || true
    rm -f "$TUNNEL_PID_FILE"
fi

# ── 2. 启动新隧道 ──
echo "$TIMESTAMP REBUILD — 创建新隧道..." >> "$MONITOR_LOG"

nohup ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -o StrictHostKeyChecking=no \
    -R 80:localhost:$PORT serveo.net 2>"$TUNNEL_RAW_LOG" &
TUNNEL_PID=$!
echo $TUNNEL_PID > "$TUNNEL_PID_FILE"

# ── 3. 等待隧道建立，提取URL ──
sleep 6
NEW_URL=""
if [ -f "$TUNNEL_RAW_LOG" ]; then
    # 从日志中提取serveo隧道URL
    NEW_URL=$(grep -o 'https://[a-z0-9-]*\.serveousercontent\.com' "$TUNNEL_RAW_LOG" | head -1)
fi

if [ -n "$NEW_URL" ]; then
    report_url "$NEW_URL"
    echo "$TIMESTAMP BIRTH $NEW_URL PID=$TUNNEL_PID" >> "$LIFECYCLE_LOG"
    echo "$TIMESTAMP NEW_TUNNEL URL=$NEW_URL PID=$TUNNEL_PID" >> "$MONITOR_LOG"
else
    echo "$TIMESTAMP NO_URL_GENERATED" >> "$FAIL_LOG"
    echo "$TIMESTAMP NO_URL_GENERATED — 未能提取隧道URL" >> "$MONITOR_LOG"
fi
