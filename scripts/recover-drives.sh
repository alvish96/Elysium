#!/usr/bin/env bash
# /usr/local/bin/recover-drives.sh
# Automated storage recovery for USB bus drops, offline SCSI nodes, and stale MergerFS pools

echo "=== [1/6] Unhooking Stale MergerFS Pool Mounts ==="
umount -l /mnt/movies_pool /mnt/tvshows_pool /mnt/audio_pool /mnt/nexus_pool 2>/dev/null || true
systemctl stop mnt-movies_pool.automount mnt-tvshows_pool.automount mnt-audio_pool.automount mnt-nexus_pool.automount 2>/dev/null || true

echo "=== [2/6] Pruning Dropped and Offline SCSI Handles ==="
for dev in /sys/block/sd*; do
    [ -d "$dev" ] || continue
    state=$(cat "$dev/device/state" 2>/dev/null || echo "unknown")
    size=$(cat "$dev/size" 2>/dev/null || echo 0)
    if [ "$size" = "0" ] || [ "$state" = "offline" ]; then
        disk=$(basename "$dev")
        echo "Pruning invalid SCSI handle: $disk (state=$state, size=$size)"
        echo 1 > "$dev/device/delete" 2>/dev/null || true
    fi
done

echo "=== [3/6] Rescanning SCSI Hosts and Refreshing Devices ==="
for host in /sys/class/scsi_host/host*/scan; do
    echo "- - -" > "$host"
done

sleep 2
udevadm trigger
udevadm settle --timeout=10 2>/dev/null || true
systemctl daemon-reload

echo "=== [4/6] Checking Filesystem Integrity on Unmounted Databoxes ==="
grep -E 'UUID=.*\/mnt\/databox_' /etc/fstab | while read -r line; do
    uuid=$(echo "$line" | grep -o 'UUID=[^ ]*' | cut -d= -f2)
    mountpoint=$(echo "$line" | awk '{print $2}')
    [ -z "$uuid" ] && continue

    dev_path="/dev/disk/by-uuid/$uuid"
    if [ -e "$dev_path" ]; then
        if ! findmnt -rn "$mountpoint" >/dev/null 2>&1; then
            echo "Running filesystem check on $mountpoint ($uuid)..."
            e2fsck -fy "$dev_path" >/dev/null 2>&1 || true
        fi
    fi
done

echo "=== [5/6] Mounting Databoxes and MergerFS Pools ==="
for box in /mnt/databox_*; do
    mount "$box" 2>/dev/null || true
done

systemctl start mnt-movies_pool.automount mnt-tvshows_pool.automount mnt-audio_pool.automount mnt-nexus_pool.automount 2>/dev/null || true
mount /mnt/movies_pool 2>/dev/null || true
mount /mnt/tvshows_pool 2>/dev/null || true
mount /mnt/audio_pool 2>/dev/null || true
mount /mnt/nexus_pool 2>/dev/null || true

echo "=== [6/6] Recycling Media Workloads in Kubernetes ==="
if command -v kubectl >/dev/null 2>&1; then
    kubectl rollout restart deployment/radarr deployment/sonarr deployment/qbittorrent deployment/jellyfin -n media 2>/dev/null || true
fi

echo "=== Recovery Complete! Active Mount Status: ==="
timeout 5s df -h | grep -E 'Filesystem|pool|databox' || echo "Notice: df check timed out, inspect mounts with findmnt."
