#!/usr/bin/env bash
set -e

LOG_FILE="/var/log/music-sync.log"

# Prevent duplicate concurrent executions
if pgrep -f "/usr/local/bin/sync-music$" >/dev/null 2>&1; then
  echo "⚠️  A music sync process is already running in the background."
  echo "👉 Stream active logs with: tail -f ${LOG_FILE}"
  exit 1
fi

echo "🎵 Launching music sync in the background..."

# Run sync-music detached in the background
nohup /usr/local/bin/sync-music > "${LOG_FILE}" 2>&1 &
BG_PID=$!

echo "🚀 Sync started successfully (PID: ${BG_PID})."
echo "📄 Log file: ${LOG_FILE}"
echo ""
echo "Helpful commands:"
echo "  • Stream live output:   tail -f ${LOG_FILE}"
echo "  • Check pod status:     kubectl get pods -n media -l app=music-sync"
echo "  • Check if running:     pgrep -fl sync-music"
