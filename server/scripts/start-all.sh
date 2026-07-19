#!/bin/bash
# 一键启动所有服务
echo "🚀 启动 PostgreSQL..."
$HOME/Applications/PostgresV16.app/Contents/Versions/16/bin/pg_ctl -D $HOME/pgdata start -l $HOME/pgdata/logfile 2>/dev/null
sleep 1

echo "🚀 启动服务端..."
cd $HOME/development/field_tracker/server && NODE_ENV=development node dist/index.js &
sleep 2

echo "🚀 启动 serveo 隧道..."
ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -R 80:localhost:3000 serveo.net &
sleep 3

echo ""
echo "=== 服务状态 ==="
curl -s http://localhost:3000/health
echo ""
echo "✅ 全部启动完成"
