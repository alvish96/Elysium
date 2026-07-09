#!/bin/bash

NODE_NAME=$(hostname)
ATLANTIS_IP="192.168.1.160"
ATLANTIS_USER="root"
REPO_DIR="$HOME/Elysium"

# Generate the profile in a temporary local folder first
LOCAL_TMP="/tmp/hwres_$NODE_NAME"

echo "Running Hardware Resource Aggregation for $NODE_NAME..."

# 1. Gather Hardware State
echo "# Hardware Profile: $NODE_NAME" > "$LOCAL_TMP"
echo "Last Updated: $(date)" >> "$LOCAL_TMP"
echo "---" >> "$LOCAL_TMP"
echo "## OS & Kernel" >> "$LOCAL_TMP"
uname -a >> "$LOCAL_TMP"
echo -e "\n## CPU" >> "$LOCAL_TMP"
lscpu | grep -E "Model name|Socket|Thread|CPU\(s\):" >> "$LOCAL_TMP"
echo -e "\n## Memory" >> "$LOCAL_TMP"
free -h >> "$LOCAL_TMP"
echo -e "\n## Block Devices (Disks)" >> "$LOCAL_TMP"
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT >> "$LOCAL_TMP"
echo -e "\n## Mounted Filesystems" >> "$LOCAL_TMP"
df -hT | grep -v tmpfs | grep -v overlay | grep -v shm >> "$LOCAL_TMP"

# 2. Routing Logic (Hub vs Spoke)
if [ "$NODE_NAME" = "atlantis" ]; then
    echo "Node is Atlantis (Hub). Copying local profile to repo..."
    cp "$LOCAL_TMP" "$REPO_DIR/cluster-init/nodes/"

    echo "Synchronizing Hub with GitHub..."
    cd "$REPO_DIR" || exit
    git fetch origin
    git pull --rebase origin main

    # Stage all hardware profiles received from the spokes
    git add cluster-init/nodes/hwres_*

    # If nothing changed across any of the 4 nodes, exit cleanly
    if git diff-index --quiet HEAD; then
        echo "No hardware changes detected across the cluster. Exiting."
        exit 0
    fi

    # Commit and push the master package
    git commit -m "chore(nodes): automated daily hardware telemetry sync from all cluster nodes"
    git push origin main
    echo "Successfully pushed cluster telemetry to GitHub."
else
    echo "Node is $NODE_NAME (Spoke). Sending profile to Atlantis via SCP..."
    # Silently transfers the file to the Atlantis repository folder over local LAN
    scp "$LOCAL_TMP" "$ATLANTIS_USER@$ATLANTIS_IP:$REPO_DIR/cluster-init/nodes/"
    echo "Successfully transferred profile to Atlantis."
fi
