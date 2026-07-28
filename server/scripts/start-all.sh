#!/bin/bash
# 一键启动所有服务
echo "🚀 启动 PostgreSQL..."
$HOME/Applications/PostgresV16.app/Contents/Versions/16/bin/pg_ctl -D $HOME/pgdata start -l $HOME/pgdata/logfile 2>/dev/null
sleep 1

echo "🚀 启动服务端..."
cd $HOME/development/field_tracker/server && NODE_ENV=development node dist/index.js &
sleep 2

echo "🚀 启动 autossh 隧道（守护脚本管理）..."
nohup bash $HOME/development/field_tracker/scripts/tunnel-autossh.sh > $HOME/logs/tunnel-autossh-daemon.log 2>&1 &
echo "  ↪ 守护脚本: $HOME/development/field_tracker/scripts/tunnel-autossh.sh"
echo "  ↪ PID: $!"

echo ""
echo "=== 服务状态 ==="
curl -s http://localhost:3000/health
echo ""
echo "✅ 全部启动完成"
