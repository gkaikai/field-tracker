#!/bin/bash
# Serveo隧道看守脚本 - 断线自动重连
while true; do
  echo "[$(date '+%H:%M:%S')] 启动Serveo隧道..."
  ssh -o StrictHostKeyChecking=no \
      -o ServerAliveInterval=10 \
      -o ServerAliveCountMax=2 \
      -o TCPKeepAlive=yes \
      -o ExitOnForwardFailure=yes \
      -R 80:localhost:3000 serveo.net 2>&1
  RC=$?
  echo "[$(date '+%H:%M:%S')] 隧道退出(code=$RC)，5秒后重连..."
  sleep 5
done
