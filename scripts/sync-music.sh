#!/usr/bin/env bash
set -eo pipefail

NAMESPACE="media"
CRONJOB="music-sync"
YAML_PATH="/root/Elysium/app-code/music-sync/music-sync-cronjob.yaml"
TIMESTAMP=$(date +%s)
JOB_NAME="manual-music-sync-${TIMESTAMP}"

cleanup() {
  echo ""
  echo "🧹 Cleaning up manual job '${JOB_NAME}'..."
  kubectl delete job "${JOB_NAME}" -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1
  echo " Done. Everything is clean."
}

trap cleanup EXIT INT TERM

echo "📋 Ensuring latest YAML configuration is applied to K3s..."
kubectl apply -f "${YAML_PATH}" >/dev/null

echo "🚀 Spawning manual sync job (${JOB_NAME})..."
kubectl create job --from=cronjob/${CRONJOB} ${JOB_NAME} -n ${NAMESPACE} >/dev/null

echo "⏳ Waiting for pod container to start..."
while ! kubectl logs -n ${NAMESPACE} job/${JOB_NAME} -f 2>/dev/null; do
  sleep 1
done

echo ""
echo "✅ Download process complete."
