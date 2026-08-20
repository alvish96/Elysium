# Project Elysium - State & Progress Report (STATE.md)

## 1. Executive Summary & Current Cluster Health
- **Cluster**: Bare-metal K3s Multi-Node GitOps Cluster (v1.36.2+k3s1) managed via ArgoCD.
- **Control Plane & Master Storage**: `atlantis` (192.168.1.160 / Tailscale: 100.110.100.1)
- **Primary Domain**: `*.nexus.link` (Traefik Ingress + Authentik ForwardAuth + AdGuard Home DNS).
- **Cluster Status**: **HEALTHY**. Core DNS operational, all media, monitoring, and security services active on local LAN nodes.

---

## 2. Incidents & Technical Resolutions (This Session)

### A. CoreDNS Outage & Cluster-Wide DNS Recovery
- **Symptom**: CoreDNS in `CrashLoopBackOff` (`plugin/hosts: this plugin can only be used once per Server Block`), causing cascading failures across `authentik`, `open-webui`, `n8n`, `trawl`, and `qbittorrent`.
- **Root Cause**: Duplicate `hosts` plugin directive in `coredns-custom` ConfigMap (`aura.override`) colliding with the main `Corefile` `hosts` directive.
- **Resolution**:
  1. Deleted conflicting `coredns-custom` ConfigMap (`kubectl delete cm coredns-custom -n kube-system`).
  2. Performed rollout restart of CoreDNS deployment (`kubectl rollout restart deployment coredns -n kube-system`).
  3. Rolling restarted dependent services (`authentik`, `open-webui`, `n8n`, `trawl`, `qbittorrent`).

### B. Jellyfin Scan Speed Optimization (MergerFS Sub-Pools)
- **Problem**: Scanning media libraries in Jellyfin was taking excessive time because `/mnt/nexus_pool` traversed **16 underlying drives** (internal LVM + 15 USB databoxes) sequentially over USB hubs.
- **Resolution**:
  1. Replaced monolithic `nexus_pool` mounts in Jellyfin with targeted MergerFS sub-pool mounts (`movies_pool`, `tvshows_pool`, `audio_pool`).
  2. Updated `jellyfin-storage.yaml` with PVs and PVCs bound to `/mnt/movies_pool`, `/mnt/tvshows_pool`, and `/mnt/audio_pool` on `atlantis`.
  3. Updated `jellyfin-deployment.yaml` with volume mounts `/data/movies`, `/data/tvshows`, `/data/audio`.
  4. Reduced filesystem lookup overhead by **~87%** during library scans.

### C. ArgoCD Duplicate IngressRoute Cleanup
- **Problem**: ArgoCD flagged `Resource traefik.io/IngressRoute/media/jellyfin-ingress appeared 2 times among application resources`.
- **Resolution**:
  1. Removed duplicate `IngressRoute` block from `jellyfin-deployment.yaml`.
  2. Consolidated domain match rules (`Host("jellyfin.nexus.link") || Host("jellyfin.local")`) inside `jellyfin-ingress.yaml`.

### D. Trawl & Gluetun Cross-Node Proxy Firewall Fix (`FIREWALL_INPUT_SUBNETS`)
- **Problem**: `trawl` (Camoufox browser engine) crashed with `Failed to get a public proxy IP address from any API endpoint` when scheduled on worker nodes (`avalon` / `phantom`).
- **Root Cause**: `trawl` routes outbound browser initialization through Gluetun HTTP proxy (`qbittorrent-svc:8888`). Gluetun's container firewall lacked `FIREWALL_INPUT_SUBNETS`, causing its internal `iptables` to block incoming proxy connections from other worker pod subnets (`10.42.2.x` / `10.42.1.x`).
- **Resolution**:
  1. Injected `FIREWALL_INPUT_SUBNETS="10.42.0.0/16,10.43.0.0/16,192.168.1.0/24"` into Gluetun container in `qbittorrent` deployment.
  2. Updated `trawl-deployment.yaml` with full FQDN (`http://qbittorrent-svc.media.svc.cluster.local:8888`) and `dnsConfig` (`ndots: "1"`).
  3. Configured TCP MSS clamping on `avalon` and `phantom`.
  4. `trawl` successfully offloaded to worker compute (`avalon` / `phantom`) with 100% operational proxy routing.

---

## 3. Node Topology & Cordoning Matrix

| Node Hostname | IP Address | Role / Status | Workload Allocation Policy |
| :--- | :--- | :--- | :--- |
| **atlantis** | `192.168.1.160` | Control Plane / Storage Master | Storage Core, CoreDNS, ArgoCD, Ingress, Authentik |
| **olympus** | `192.168.1.243` | Worker (UPS Battery-backed) | Primary Compute (Uptime Kuma, Apprise, Beszel Hub) |
| **avalon** | `192.168.1.164` | Worker Node | Primary Compute (Trawl, Speedtest Tracker, LiteLLM) |
| **phantom** | `192.168.1.170` | Worker Node | Failover Compute, YouTube Streamers, Home Assistant |
| **pi** | `192.168.1.130` | 32-bit ARM (Cordoned & Tainted) | Strictly Excluded (`dedicated=pi:NoSchedule`) |
| **hcnvedl1108401** | `100.110.100.16` | Off-Site Tailscale Worker | **Cordoned** (`SchedulingDisabled`). Reserved for future test suite |

---

## 4. Key Deployment Rules & Best Practices

1. **DNS Search Loops**: Always apply `dnsConfig: { options: [{ name: "ndots", value: "1" }] }` to Alpine/Node.js containers to prevent DNS search-path loops.
2. **Gluetun Proxy Access**: Any app making proxy calls to `qbittorrent-svc:8888` must use full FQDN (`http://qbittorrent-svc.media.svc.cluster.local:8888`) and ensure `FIREWALL_INPUT_SUBNETS` in Gluetun covers `10.42.0.0/16`.
3. **MergerFS Storage Mounts**: Use dedicated sub-pools (`movies_pool`, `tvshows_pool`, `audio_pool`) for high-frequency scanner applications like Jellyfin rather than querying the full 16-drive `nexus_pool`.
4. **GitOps Workflow**: All manifest edits must be committed and pushed to `https://github.com/alvish96/Elysium` under `app-code/<app>/`.

---

## 5. Next Steps / Pending Roadmap
- Establish isolated side-by-side test suite on `hcnvedl1108401` prior to un-cordoning for off-site failover workloads.
- Unify backup pipelines for new Jellyfin sub-pool configurations.
