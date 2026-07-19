#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "========================================"
echo " Field Tracker - Production Deploy"
echo "========================================"

# 1. Pull latest code
echo "[1/5] Pulling latest code..."
git pull origin main

# 2. Install dependencies
echo "[2/5] Installing dependencies..."
npm install --production

# 3. Build project
echo "[3/5] Building project..."
npm run build

# 4. Restart PM2 process
echo "[4/5] Restarting PM2 process..."
pm2 startOrReload ecosystem.config.js --env production

# 5. Save PM2 process list
echo "[5/5] Saving PM2 process list..."
pm2 save

echo "========================================"
echo " Deploy complete! Process status:"
pm2 show field-tracker
echo "========================================"
