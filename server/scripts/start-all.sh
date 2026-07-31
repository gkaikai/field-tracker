#!/bin/bash
# 一键启动所有服务
echo "🚀 启动 PostgreSQL..."
$HOME/Applications/PostgresV16.app/Contents/Versions/16/bin/pg_ctl -D $HOME/pgdata start -l $HOME/pgdata/logfile 2>/dev/null
sleep 1

echo "🚀 启动服务端..."
cd $HOME/development/field_tracker/server && NODE_ENV=development node dist/index.js &
sleep 2

echo "🚀 启动隧道监督（tunnel-keepalive.sh，cron */5 持续监督）..."
bash $HOME/development/field_tracker/scripts/tunnel-keepalive.sh >/dev/null 2>&1 &
echo "  ↪ 监督脚本: $HOME/development/field_tracker/scripts/tunnel-keepalive.sh"
echo "  ↪ PID: $!"

echo ""
echo "=== 服务状态 ==="
curl -s http://localhost:3000/health
echo ""
echo "✅ 全部启动完成"
