#!/bin/bash
# Serveo 隧道自动重连脚本
# 隧道断开后自动重连，并记录最新URL
# 用法: bash keep_tunnel_alive.sh &

TUNNEL_LOG="/Users/openclaw-gkf/development/field_tracker/tunnel_url.txt"
TUNNEL_CURRENT="/Users/openclaw-gkf/development/field_tracker/current_tunnel_url.txt"

echo "[$(date)] 隧道守护进程启动" >> "$TUNNEL_LOG"

while true; do
  URL=$(ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=30 \
    -R 80:localhost:3000 serveo.net 2>&1 | \
    sed -n 's/.*\(https:\/\/[^ ]*\.serveousercontent\.com\).*/\1/p' | head -1)

  echo "[$(date)] Tunnel URL: $URL" >> "$TUNNEL_LOG"
  echo "$URL" > "$TUNNEL_CURRENT"

  # 等待SSH进程退出（隧道断开）
  wait $!
  echo "[$(date)] 隧道断开，5秒后重连..." >> "$TUNNEL_LOG"
  sleep 5
done
