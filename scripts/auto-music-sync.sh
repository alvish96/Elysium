#!/usr/bin/env bash
set -e

YAML_PATH="/root/Elysium/app-code/music-sync/music-sync-cronjob.yaml"
echo "[$(date)] Change detected in ${YAML_PATH}"

sleep 1
kubectl apply -f "${YAML_PATH}"
/usr/local/bin/sync-music-bg
