# Nexus Music v2.1 ("Galactic Command") — Restoration & Rollback Runbook

This runbook documents the exact procedures required to restore or roll back the **Nexus Music** platform (`http://sync.nexus.link`) to the verified **v2.1 Production Release** (`v2.1-production`).

---

## 1. System & Release Architecture

* **Release Tag:** `v2.1-production` (and tag `savepoint-v2.2-main-promoted`)
* **Host Control Plane:** `atlantis` (`192.168.1.160`)
* **Repository Path:** `/root/Elysium` (or `~/Elysium`)
* **Namespace:** `media`
* **Deployments:**
  * `nexus-sync-api` (FastAPI backend + Static V2.1 UI served at root `/` and `/tracks`)
  * `nexus-sync-worker` (Async queue worker with yt-dlp & FFmpeg 320kbps transcoding)
  * `nexus-sync-redis` (Task broker & pub/sub state engine)
* **Storage Paths:**
  * Master Tracks Pool: `/mnt/audio_pool/music/tracks/`
  * Playlists Pool: `/mnt/audio_pool/music/playlists/`
* **Active Routing:**
  * `http://sync.nexus.link/` -> Galactic Command UI v2.1
  * `http://sync.nexus.link/tracks` -> Downloaded Tracks Archive & Web Audio Audition Player
  * `http://sync.nexus.link/v1` or `/legacy` -> Legacy v1 interface

---

## 2. Emergency 60-Second Rollback (Fast Code Reset)

If a future experimental patch or update breaks the frontend, API, or worker, execute this command block on **`atlantis`** to roll back only the Nexus Music backend files to the `v2.1-production` tag without altering other cluster workloads:

```bash
cd /root/Elysium

# 1. Fetch latest tags from remote
git fetch origin --tags

# 2. Checkout the backend files strictly from the production tag
git checkout v2.1-production -- nexus-music/src/backend/

# 3. Clean up any untracked experimental test files
git clean -fd nexus-music/src/backend/

# 4. Restart API and Worker pods to load the verified code
kubectl rollout restart deployment/nexus-sync-api deployment/nexus-sync-worker -n media

# 5. Wait for rollouts to finish
kubectl rollout status deployment/nexus-sync-api -n media
kubectl rollout status deployment/nexus-sync-worker -n media
## 3. Full Repository Rollback (Bare-Metal Git Reset)
If multiple repository files or directories are compromised and you need to reset the entire Git working tree back to the exact commit tagged by v2.1-production:

Bash
cd /root/Elysium

# 1. Stash any uncommitted manual edits
git stash --include-untracked

# 2. Hard reset branch to the production release tag
git fetch origin --tags
git reset --hard v2.1-production

# 3. Force restart the workloads
kubectl rollout restart deployment/nexus-sync-api deployment/nexus-sync-worker -n media
kubectl rollout status deployment/nexus-sync-api -n media
kubectl rollout status deployment/nexus-sync-worker -n media

## 4. Queue Recovery & Stale State Purge
If downloads become stuck at 0% or tasks are orphaned due to an abrupt shutdown or invalid payload:

Bash
# 1. Flush active streams and clear cancellation sets in Redis
kubectl exec -it -n media deployment/nexus-sync-api -- /opt/venv/bin/python -c '
import redis, os
r = redis.Redis(host=os.getenv("REDIS_HOST", "nexus-sync-redis-svc.media.svc.cluster.local"), port=6379, db=0)
r.delete("nexus:downloads:active")
r.delete("nexus:downloads:cancelled")
print("Cleared active and cancelled download sets in Redis.")
'

# 2. Purge leftover temporary download directories on worker node
kubectl exec -it -n media deployment/nexus-sync-worker -- bash -c 'rm -rf /tmp/yt_dl_* /tmp/yt_pl_*'

# 3. Restart the background worker
kubectl rollout restart deployment/nexus-sync-worker -n media

## 5. Post-Rollback Health Verification
Run these commands on atlantis to verify system operational readiness:

# 1. Check Pod Statuses
Bash
kubectl get pods -n media -l 'app in (nexus-sync-api, nexus-sync-worker, nexus-sync-redis)'

# 2. Verify Worker Log Stream
Bash
kubectl logs -n media deployment/nexus-sync-worker --tail=25

# 3. Verify HTTP Endpoints
Bash
curl -s -o /dev/null -w "%{http_code}\n" [http://127.0.0.1:8000/](http://127.0.0.1:8000/)
curl -s -o /dev/null -w "%{http_code}\n" [http://127.0.0.1:8000/tracks](http://127.0.0.1:8000/tracks)
curl -s -o /dev/null -w "%{http_code}\n" [http://127.0.0.1:8000/v1](http://127.0.0.1:8000/v1)
## 4. Browser Smoke Test
Visit http://sync.nexus.link and perform a hard refresh (Cmd + Shift + R or Ctrl + F5).

Verify Sector 01 accepts YouTube links and Sector 02 tracks download progress smoothly (5% -> 20% -> 85% -> 100%).

Verify Sector 03 shows playlist rows with locked right-hand action controls (SYNC ON/OFF, PRIVATE/PUBLIC, ⚡ SYNC, ✕ DELETE).

Click 🎵 DOWNLOADED TRACKS ↗ in the top HUD and verify in-browser MP3 streaming works.
