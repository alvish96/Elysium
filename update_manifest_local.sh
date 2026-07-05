#!/bin/bash

# Configuration Paths
REPO_DIR="/root/Elysium"
MANIFEST_FILE="${REPO_DIR}/hwres_atlantis"
TMP_MANIFEST="${REPO_DIR}/hwres_atlantis.tmp"

cd "$REPO_DIR" || exit 1

# Pull down any remote repository changes prior to baseline evaluation
git pull origin main --ff-only

echo "Generating raw environment details locally..."

# Aggregate real-time metrics and construct the manifest structural data
cat << INNER_EOF > "$TMP_MANIFEST"
# System Profile: Atlantis

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
$(df -h | grep -E '^/dev/|pool|mergerfs|internal')
\`\`\`

### File System Table Configuration (/etc/fstab)
\`\`\`text
$(cat /etc/fstab | grep -v '^#' | grep -v '^$')
\`\`\`

## 4. Persistent Storage Pools & MergerFS Layout
- **Pool Name:** nexus_pool
- **Mount Path:** /mnt/nexus_pool
- **Consolidated Elements:** /mnt/internal combined with 14 individual storage drives (\`/mnt/databox_01_*\` through \`/mnt/databox_14_*\`).
- **Removable Flash Dev Exception:** \`/dev/sdo\` (59.5G) is excluded from the array to eliminate boot dependency vulnerabilities.

## 5. Kubernetes Environment State
- **Engine Type:** K3s (Lightweight Kubernetes)
- **Deployment Strategy:** Clean-slate blueprint targeting ArgoCD-driven orchestrations.
- **Persistent Volume Base Path:** Default K3s path \`/var/lib/rancher/k3s/storage/\` alongside targeted persistent volume bindings rooted inside \`/mnt/nexus_pool/\`.
INNER_EOF

# Verify if changes actually occurred compared to the previous manifest version
if ! cmp -s "$MANIFEST_FILE" "$TMP_MANIFEST"; then
    echo "Changes detected in system infrastructure. Updating manifest repository..."
    mv "$TMP_MANIFEST" "$MANIFEST_FILE"
    
    # Execute non-interactive Git life cycle
    git add "$MANIFEST_FILE"
    git commit -m "chore: automated local refresh of atlantis configuration blueprint [skip ci]"
    git push origin main
    echo "Manifest successfully synced to GitHub locally."
else
    echo "No structural environmental adjustments found. Skipping commit."
    rm "$TMP_MANIFEST"
fi
