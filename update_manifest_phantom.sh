#!/bin/bash
# Phantom Automated Local Architecture Manifest Sync Script

REPO_DIR="/root/Elysium"
MANIFEST_FILE="${REPO_DIR}/hwres_phantom"
TMP_MANIFEST="${REPO_DIR}/hwres_phantom.tmp"

cd "$REPO_DIR" || exit 1
# Keep local repo branches synchronized
git pull origin main --ff-only

echo "Compiling current localized system state for Phantom..."

cat << INNER_EOF > "$TMP_MANIFEST"
# System Profile: Phantom

## 1. Core Operating System
- **Hostname:** $(hostname)
- **OS:** $(grep -w "PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
- **Kernel:** $(uname -r)
- **Architecture:** $(uname -m)

## 2. Hardware Resource Metrics
- **CPU Threads:** $(nproc)
- **Memory Profile:**
$(free -h)

## 3. Storage Architecture & Block Topology
### Block Device Enumeration (lsblk)
\`\`\`text
$(lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,MOUNTPOINTS)
\`\`\`

### Active Filesystem Allocation (df -h)
\`\`\`text
$(df -h | grep -E '^/dev/|^/|tmpfs')
\`\`\`

## 4. Kubernetes Environment State
- **Engine Type:** K3s (Lightweight Kubernetes - Worker Agent Node)
- **Master Control Plane Target:** https://192.168.1.160:6443
- **Runtime Agent Footprint:** $(systemctl is-active k3s-agent)
- **Kubelet Version Context:** $(k3s --version 2>/dev/null || echo "N/A")
INNER_EOF

# Evaluate structural differences against previous state snapshot
if ! cmp -s "$MANIFEST_FILE" "$TMP_MANIFEST"; then
    echo "Structural evolution detected on Phantom. Syncing architecture updates to GitHub..."
    mv "$TMP_MANIFEST" "$MANIFEST_FILE"
    git add "$MANIFEST_FILE"
    git commit -m "chore: automated local refresh of phantom configuration blueprint [skip ci]"
    git push origin main
else
    echo "Phantom infrastructure remains aligned. Clearing temporary tracking buffers."
    rm "$TMP_MANIFEST"
fi
