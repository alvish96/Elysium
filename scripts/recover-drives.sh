#!/bin/bash
set -e

echo "=== [1/6] Unhooking Stale MergerFS Pool Mounts ==="
# Unmount pools lazily so hung I/O doesn't freeze the remount
umount -l /mnt/tvshows_pool 2>/dev/null || true
umount -l /mnt/movies_pool 2>/dev/null || true
umount -l /mnt/audio_pool 2>/dev/null || true
umount -l /mnt/nexus_pool 2>/dev/null || true

echo "=== [2/6] Deleting 0B Dead SCSI Handles ==="
# Clear broken device stubs (like sdg showing 0B)
for dev in /sys/block/sd*; do
    if [ -f "$dev/size" ] && [ "$(cat "$dev/size" 2>/dev/null)" = "0" ]; then
        disk=$(basename "$dev")
        echo "Pruning dead device node: $disk"
        echo 1 > "$dev/device/delete" 2>/dev/null || true
    fi
done

echo "=== [3/6] Rescanning SCSI Bus & Refreshing Udev ==="
for host in /sys/class/scsi_host/host*/scan; do
    echo "- - -" > "$host"
done

udevadm trigger
udevadm settle --timeout=10

echo "=== [4/6] Reloading Systemd & Mounting Databoxes ==="
systemctl daemon-reload

# Mount all drives defined in /etc/fstab
mount -a

# Ensure every databox folder attempt is explicitly touched
for box in /mnt/databox_*; do
    mount "$box" 2>/dev/null || true
done

echo "=== [5/6] Remounting MergerFS Pools ==="
systemctl restart mnt-movies_pool.automount mnt-tvshows_pool.automount mnt-audio_pool.automount mnt-nexus_pool.automount 2>/dev/null || true

mount /mnt/movies_pool 2>/dev/null || true
mount /mnt/tvshows_pool 2>/dev/null || true
mount /mnt/audio_pool 2>/dev/null || true
mount /mnt/nexus_pool 2>/dev/null || true

echo "=== [6/6] Cycling Stuck Media Workloads (Optional) ==="
if command -v kubectl &>/dev/null; then
    kubectl rollout restart deployment/sonarr deployment/radarr deployment/qbittorrent -n media 2>/dev/null || true
fi

echo "=== Storage Recovery Complete! Current Status: ==="
df -h | grep -E 'Filesystem|pool|databox'
