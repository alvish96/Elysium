---

### 2. `STATE.md`

```markdown
# Elysium K3s Cluster: Dynamic Progress Ledger

## 1. Project Milestone Checklist

- [x] **Phase 1: Cluster Baseline & Storage Consolidation**
  - [x] Initialized K3s multi-node cluster (`atlantis`, `phantom`, `olympus`, `avalon`, `pi`).
  - [x] Configured `/etc/fstab` with static UUIDs for 14 EXT4 databox drives.
  - [x] Established consolidated `/mnt/nexus_pool` MergerFS storage layer.
  - [x] Cordoned and tainted 32-bit `pi` node (`dedicated=pi:NoSchedule`).

- [x] **Phase 2: GitOps Infrastructure & Network Hardening**
  - [x] ArgoCD SSH authentication mapped via `~/Elysium-essentials/argocd-repo-secret.yaml`.
  - [x] Re-architected GitOps into strict "App of Apps" layout (`argocd-apps/` vs `app-code/`).
  - [x] Implemented Hub-and-Spoke Telemetry Grid (`update_hwres.sh` via SCP to `atlantis`).

- [x] **Phase 3: Core Media & VPN Download Engine**
  - [x] Deployed Jellyfin with expanded `/mnt` storage visibility.
  - [x] Deployed qBittorrent + Gluetun WireGuard VPN Sidecar.
  - [x] Deployed Trawl (FlareSolverr) for Cloudflare challenge solving.
  - [x] Deployed full Arr stack (Prowlarr, Radarr, Sonarr, Lidarr, Whisparr, Bazarr).

- [x] **Phase 4: Ingress, Domain & SSO Authentication**
  - [x] Configured AdGuard Home DNS rewrites for `*.nexus.link` / `*.aura`.
  - [x] Deployed Authentik Domain-Level ForwardAuth with Traefik Middlewares broken down by namespace (`forwardauth-middleware-media.yaml`, etc.).
  - [x] Pinned CoreDNS and Security Stack to `atlantis`.

- [x] **Phase 5: Notification Gateway & Automation**
  - [x] Deployed stateless Apprise Notification Gateway (`app-code/apprise/`).
  - [x] Enabled kernel IP forwarding (`net.ipv4.ip_forward=1`) and TCP MSS clamping on worker nodes to fix egress TLS timeouts.
  - [x] Deployed `n8n` workflow engine (`app-code/n8n/`) with dedicated postgres.

- [x] **Phase 6: Monitoring & Telemetry Mesh**
  - [x] Deployed Uptime Kuma for service pings (`app-code/uptimekuma/`).
  - [x] Deployed Beszel (Hub + Agents) for lightweight cluster metrics (`app-code/beszel/`).
  - [x] Deployed Glances DaemonSet natively supporting multi-arch (`linux/arm64` for `pi`) (`app-code/glances/`).
  - [x] Deployed Scrutiny for S.M.A.R.T. drive health monitoring (`app-code/scrutiny/`).
  - [x] Deployed Netdata for deep infrastructure telemetry (`app-code/netdata/`).

- [x] **Phase 7: AI Infrastructure & Local LLMs**
  - [x] Configured out-of-band `ai-secrets.yaml` in `Elysium-essentials`.
  - [x] Deployed LiteLLM proxy (`app-code/litellm/`).
  - [x] Deployed Open-WebUI chat interface (`app-code/open-webui/`).

- [ ] **Phase 8: Backup & Disaster Recovery (Active Phase)**
  - [x] Generated Restic credentials (`RESTIC_MASTER_PASSWORD.txt`).
  - [x] Created `app-code/backups/restic-cronjob.yaml`.
  - [ ] **Next Step:** Verify automated Duplicati / Restic backup schedules for `/mnt/internal/appdata`.
  - [ ] **Next Step:** Perform manual Postgres DB dumps for Authentik, n8n, and Open-WebUI to confirm restore capability.

---

## 2. Notification Integration Registry (`http://apprise-svc.monitoring.svc.cluster.local:8000`)

| Service | Target URL / Endpoint | Configuration Type / Notes | Status |
| :--- | :--- | :--- | :--- |
| **Arr Stack (Radarr/Sonarr/etc)** | `http://apprise-svc.monitoring:8000` | Native Apprise + Discord Stateless URL | **Active** |
| **Jellyseerr** | `.../notify/?urls=discord://...` | Custom Webhook (POST JSON) | **Active** |
| **Uptime Kuma** | `.../notify/` | Native Apprise Notification Type | **Active** |
| **Beszel Hub** | `.../notify/` | Webhook Integration | **Active** |
| **Speedtest Tracker**| `.../notify/` | Webhook Integration | **Active** |

---

## 3. Operational Runbook & Maintenance Snippets

### A. Uptime Kuma / Apprise Cross-Node Fix (`ndots: 1`)
When monitoring services across nodes via Alpine containers, always apply `dnsConfig`:
```yaml
dnsPolicy: ClusterFirst
dnsConfig:
  options:
    - name: ndots
      value: "1"

### B. Worker Node Network Egress Fix (Kernel IP Forwarding)
If worker nodes experience 10-second TLS timeouts reaching external APIs (like Discord):

Bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1 2>/dev/null || true
sudo iptables -P FORWARD ACCEPT
sudo iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf && sudo sysctl -p

### C. Emergency Authentik Database Reset
If a power failure corrupts PostgreSQL session locks causing 500/503 errors:

Bash
kubectl scale deployment authentik-server authentik-worker -n security --replicas=0
kubectl exec -n security deployment/authentik-redis -- redis-cli FLUSHALL
kubectl exec -n security deployment/authentik-postgres -- psql -U authentik -d postgres \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'authentik' AND pid <> pg_backend_pid();" \
  -c "DROP DATABASE IF EXISTS authentik WITH (FORCE);" \
  -c "CREATE DATABASE authentik OWNER authentik;"
kubectl scale deployment authentik-server authentik-worker -n security --replicas=1
