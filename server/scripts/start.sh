#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Ensure logs directory exists
mkdir -p logs

echo "========================================"
echo " Field Tracker - Start Service"
echo "========================================"

# Source production environment
set -a
source .env.production
set +a

# Check if PM2 process already exists
if pm2 show field-tracker &>/dev/null 2>&1; then
  echo "[INFO] Process 'field-tracker' already exists, reloading..."
  pm2 reload ecosystem.config.js --env production
else
  echo "[INFO] Starting 'field-tracker' for the first time..."
  pm2 start ecosystem.config.js --env production
fi

pm2 save

echo "[OK] Service started."
echo "     Logs: $PROJECT_DIR/logs/"
echo "     Status: pm2 show field-tracker"
