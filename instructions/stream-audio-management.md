# YouTube Stream Audio Management Runbook

This document provides step-by-step instructions for downloading, replacing, or reverting background audio tracks on the live streaming pipeline hosted on **phantom** and managed from **atlantis**.

---

## 1. Architecture Overview

* **Host Node:** `phantom` (`192.168.1.170`)
* **Storage Path on Phantom:** `/mnt/phantom_share/appdata/youtube-stream/audio.mp3`
* **Container Mount:** `/tmp/stream-run/audio.mp3` (via PersistentVolumeClaim `youtube-stream-local-pvc`)
* **Streaming Engine:** FFmpeg running inside `youtube-streamer-tandberg` pod in namespace `media`
* **Auto-Fallback Behavior:**
  * If `/tmp/stream-run/audio.mp3` exists: FFmpeg loops it continuously using `-stream_loop -1`.
  * If the file does not exist: FFmpeg automatically falls back to silent audio (`anullsrc`) without crashing.

---

## 2. Prerequisites (One-Time Setup on Phantom)

Ensure `yt-dlp` and `ffmpeg` are installed on **phantom** to fetch and convert audio streams:


# Run on phantom:
curl -L [https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp](https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp) -o /usr/local/bin/yt-dlp
chmod a+rx /usr/local/bin/yt-dlp
apt-get update && apt-get install -y ffmpeg


## 3. How to Download or Replace the Background Track
To replace the background track with a new YouTube link or audio source:

Step A: Download & Extract Audio on Phantom
Log into phantom as root and run:


mkdir -p /mnt/phantom_share/appdata/youtube-stream
rm -f /mnt/phantom_share/appdata/youtube-stream/audio.mp3

# Download and convert track directly to audio.mp3
yt-dlp -x --audio-format mp3 \
  --no-playlist \
  -o "/mnt/phantom_share/appdata/youtube-stream/audio.mp3" \
  "<YOUTUBE_URL>"
Verification:


ls -lh /mnt/phantom_share/appdata/youtube-stream/audio.mp3
Ensure the file size is non-zero (typically several megabytes).

Step B: Restart the Streamer Pod on Atlantis
Log into atlantis and force the streaming pod to reload:


kubectl delete pod -n media -l app=youtube-streamer-tandberg --force --grace-period=0


Step C: Verify Logs
Watch the pod logs to ensure the audio track was picked up:


kubectl logs -n media deployment/youtube-streamer-tandberg -f --tail=30
Look for:


Found /tmp/stream-run/audio.mp3. Looping background audio track...
Followed by active encoding metrics (frame= ... fps=30 ...).



## 4. How to Use a Local Audio File (MP3)
If you have your own MP3 or AAC file on your machine or on atlantis:

Copy the file to phantom:


scp /path/to/my-track.mp3 root@192.168.1.170:/mnt/phantom_share/appdata/youtube-stream/audio.mp3
Restart the pod on atlantis:


kubectl delete pod -n media -l app=youtube-streamer-tandberg --force --grace-period=0



## 5. How to Revert to Silent Audio
If you want to stream video without background music:

Delete the audio file on phantom:


rm -f /mnt/phantom_share/appdata/youtube-stream/audio.mp3
Restart the pod on atlantis:


kubectl delete pod -n media -l app=youtube-streamer-tandberg --force --grace-period=0
The pod will print:


Notice: /tmp/stream-run/audio.mp3 not found. Falling back to silent audio.
