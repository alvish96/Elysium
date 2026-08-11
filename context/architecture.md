Elysium K3s Cluster: System Architecture & Static Blueprint

## 1. Node Topology & Hardware Matrix
* **Cluster Management:** K3s Multi-Node GitOps Cluster running version `v1.36.2+k3s1`.
* **Control Plane / Primary Storage Core:**
  * `atlantis` (`192.168.1.160` | Ubuntu 24.04.4 LTS | Kernel `6.8.0-124-generic`)
  * **Role:** K3s Control Plane, MergerFS Storage Pool Master, CoreDNS, ArgoCD, Security Stack (Authentik/PostgreSQL/Redis), Traefik Ingress.
* **Worker Compute Nodes:**
  * `olympus` (`192.168.1.243` | Ubuntu 24.04.4 LTS | Kernel `6.8.0-124-generic`)
  * `avalon` (`192.168.1.164` | Ubuntu / Debian 64-bit)
  * `phantom` (`192.168.1.170` | Debian 11 Bullseye | Kernel `5.10.0-9-amd64`)
* **Cordoned / Incompatible Node:**
  * `pi` / `raspberrypi` (`192.168.1.130` / `192.168.1.131` | Raspbian 12 Bookworm armv7l)
  * **Status:** Cordoned & Tainted (`dedicated=pi:NoSchedule`). Excluded from standard workloads due to 32-bit architecture constraints. Requires multi-arch images (e.g., `linux/arm64` for Glances DaemonSet).

---

## 2. Storage Infrastructure (`atlantis`)

### Host Drives & Physical Mounts
* **OS / Root Drive:** `/dev/sda` (`/`).
* **Internal LVM Drive:** `/dev/mapper/ubuntu--vg-internal` mounted on `/mnt/internal`.
* **Databox Array:** 14 static EXT4 hard drives mounted sequentially via static UUIDs in `/etc/fstab` with `x-systemd.device-timeout=10` to `/mnt/databox_01` through `/mnt/databox_14`.

### Consolidated MergerFS Pool
* **Mount Point:** `/mnt/nexus_pool`
* **FSTab Entry:**
  ```fstab
  /mnt/internal:/mnt/databox_* /mnt/nexus_pool fuse.mergerfs defaults,allow_other,use_ino,cache.files=partial,dropcacheonclose=true,category.create=mfs,fsname=nexus_pool,nofail 0 0
Permissions: Host paths set to chmod -R 755 across /mnt, /mnt/databox_*, and /mnt/nexus_pool with allow_other FUSE flag to ensure non-root container processes (UID 1000/991) can traverse directories.

AppData State Preservation: Critical databases, configurations, and cache files are pinned to /mnt/internal/appdata/<app_name> on atlantis to survive worker node reboots and power outages.

## 3. Network, DNS & Single Sign-On (SSO) Stack
Domain & Ingress Setup
Primary TLDs: *.nexus.link and *.aura.

DNS Resolution Authority: AdGuard Home running on atlantis host network (192.168.1.160:53) with wildcard DNS rewrites pointing to 100.110.100.1 / 192.168.1.160.

Tailscale Integration: Tailscale Admin Console Global Nameservers point to AdGuard Home IP with Override local DNS enabled. Linux nodes run tailscale up --accept-dns --ssh.

CoreDNS & Cluster Internal DNS
Placement: Pinned strictly to atlantis (nodeSelector: kubernetes.io/hostname: atlantis).

Upstream Forwarding: Configured in coredns-custom.yaml to forward non-cluster queries directly to AdGuard Home (192.168.1.160) to avoid loopback (127.0.0.53) crashes on worker nodes.

Alpine Linux ndots: 1 Rule: All deployments running Alpine Linux or Musl libc (e.g., Apprise, Uptime Kuma) enforce dnsConfig ndots: "1" to prevent 10-second DNS search domain loops.

Authentik Domain-Level ForwardAuth
Placement: Core DB/Redis and traefik are pinned to atlantis to eliminate cross-node DB latency.

Proxy Provider: Mode: ForwardAuth (domain level) | Cookie Domain: nexus.link (or aura).

In-Namespace Middlewares: Deployed cleanly in respective namespaces (forwardauth-middleware-media.yaml, forwardauth-middleware-monitoring.yaml).

## 4. GitOps Repository Hierarchy & Secrets Architecture
The cluster utilizes a strict separation between version-controlled GitOps manifests ("App of Apps" pattern) and out-of-band secret storage.

### A. Non-Versioned Secrets Directory (~/Elysium-essentials/)
Stored on atlantis outside of Git to prevent credential leaks:

Plaintext
~/Elysium-essentials/
├── RESTIC_MASTER_PASSWORD.txt    # Encryption key for Restic backups
├── ai-secrets.yaml               # LiteLLM/Open-WebUI API tokens
└── argocd-repo-secret.yaml       # ArgoCD GitHub SSH Private Key mapping
B. Versioned GitOps Directory (~/Elysium/)
Plaintext
~/Elysium/
├── app-code/                     # 1. RAW APPLICATION MANIFESTS
│   ├── adguard/                  # DNS & Adblocking
│   ├── apprise/                  # Universal Notification Gateway
│   ├── authentik/                # SSO, Middlewares, CoreDNS tweaks
│   ├── backups/                  # Restic cronjobs & storage
│   ├── bazarr/                   # Subtitle Manager
│   ├── beszel/                   # Lightweight monitoring hub & agents
│   ├── browser/                  # Isolated web browser container
│   ├── filebrowser/              # Web-based file management
│   ├── glances/                  # Node hardware telemetry (Multi-arch DaemonSet)
│   ├── healthchecks/             # Node pingers
│   ├── homarr/                   # Main Service Dashboard
│   ├── homeassistant/            # Smart Home Hub
│   ├── jellyfin/                 # Media Server
│   ├── jellyseerr/               # Media Request Engine
│   ├── lidarr/                   # Music Indexer
│   ├── litellm/                  # AI Model Proxy
│   ├── local-sharing/            # Network file drop
│   ├── n8n/                      # Automation & Workflow Engine
│   ├── netdata/                  # Real-time infrastructure monitoring
│   ├── open-webui/               # Chat Interface for AI models
│   ├── prowlarr/                 # Indexer Coordinator
│   ├── qbittorrent/              # Download Client + VPN Sidecar
│   ├── radarr/                   # Movie Management
│   ├── routing/                  # ArgoCD Ingress
│   ├── scrutiny/                 # Hard Drive S.M.A.R.T. Monitoring
│   ├── sonarr/                   # TV Show Management
│   ├── speedtest-tracker/        # Network speed logging
│   ├── stream/                   # FFmpeg transcoders (sidecam, sjcam, youtube)
│   ├── trawl/                    # FlareSolverr Anti-bot bypass
│   ├── ttyd/                     # Web-based terminal access
│   ├── uptimekuma/               # Uptime monitoring
│   └── whisparr/                 # Adult content indexer
│
├── argocd-apps/                  # 2. ARGOCD WRAPPERS ("App of Apps")
│   ├── adguard-app.yaml
│   ├── apprise-app.yaml
│   ├── backups-app.yaml
│   ├── ... (Matches app-code 1:1)
│
├── cluster-init/                 # 3. NODE BOOTSTRAPPING & TELEMETRY
│   ├── nodes/
│   │   ├── hwres_atlantis
│   │   ├── hwres_olympus
│   │   ├── hwres_phantom
│   │   └── hwres_pi
│   └── update_hwres.sh           # SCP/Git push script for hardware logs
│
├── argocd-ingress.yaml
├── cluster-registry.yaml
├── cluster_ports.md
├── elysium_chat_import.json
└── elysium_cluster_spec.md

## 5. Workload Security & Pod Scheduling Policies
Standardized Security Context
Uses native pod-level unconfined contexts across standard pods (Kubernetes v1.36+):

YAML
securityContext:
  seccompProfile:
    type: Unconfined
  appArmorProfile:
    type: Unconfined
Pod Placement Rules
Control Plane Core (atlantis): SQLite/Database apps, CoreDNS, ArgoCD Stack, Security Stack, Routing, Storage Management.

Stateless Compute & Processing (phantom / olympus / avalon): Apprise (weighted affinity), FlareSolverr/Trawl.

DaemonSets (glances): Multi-arch deployments targeting all nodes, automatically mapping linux/arm64 for pi and linux/amd64 for standard compute nodes.

Elysium K3s Cluster: System Architecture & Static Blueprint

## 1. Node Topology & Hardware Matrix
* **Cluster Management:** K3s Multi-Node GitOps Cluster running version `v1.36.2+k3s1`.
* **Control Plane / Primary Storage Core:**
  * `atlantis` (`192.168.1.160` | Ubuntu 24.04.4 LTS | Kernel `6.8.0-124-generic`)
  * **Role:** K3s Control Plane, MergerFS Storage Pool Master, CoreDNS, ArgoCD, Security Stack (Authentik/PostgreSQL/Redis), Traefik Ingress.
* **Worker Compute Nodes:**
  * `olympus` (`192.168.1.243` | Ubuntu 24.04.4 LTS | Kernel `6.8.0-124-generic`)
  * `avalon` (`192.168.1.164` | Ubuntu / Debian 64-bit)
  * `phantom` (`192.168.1.170` | Debian 11 Bullseye | Kernel `5.10.0-9-amd64`)
* **Cordoned / Incompatible Node:**
  * `pi` / `raspberrypi` (`192.168.1.130` / `192.168.1.131` | Raspbian 12 Bookworm armv7l)
  * **Status:** Cordoned & Tainted (`dedicated=pi:NoSchedule`). Excluded from standard workloads due to 32-bit architecture constraints. Requires multi-arch images (e.g., `linux/arm64` for Glances DaemonSet).

---

## 2. Storage Infrastructure (`atlantis`)

### Host Drives & Physical Mounts
* **OS / Root Drive:** `/dev/sda` (`/`).
* **Internal LVM Drive:** `/dev/mapper/ubuntu--vg-internal` mounted on `/mnt/internal`.
* **Databox Array:** 14 static EXT4 hard drives mounted sequentially via static UUIDs in `/etc/fstab` with `x-systemd.device-timeout=10` to `/mnt/databox_01` through `/mnt/databox_14`.

### Consolidated MergerFS Pool
* **Mount Point:** `/mnt/nexus_pool`
* **FSTab Entry:**
  ```fstab
  /mnt/internal:/mnt/databox_* /mnt/nexus_pool fuse.mergerfs defaults,allow_other,use_ino,cache.files=partial,dropcacheonclose=true,category.create=mfs,fsname=nexus_pool,nofail 0 0
Permissions: Host paths set to chmod -R 755 across /mnt, /mnt/databox_*, and /mnt/nexus_pool with allow_other FUSE flag to ensure non-root container processes (UID 1000/991) can traverse directories.

AppData State Preservation: Critical databases, configurations, and cache files are pinned to /mnt/internal/appdata/<app_name> on atlantis to survive worker node reboots and power outages.

## 3. Network, DNS & Single Sign-On (SSO) Stack
Domain & Ingress Setup
Primary TLDs: *.nexus.link and *.aura.

DNS Resolution Authority: AdGuard Home running on atlantis host network (192.168.1.160:53) with wildcard DNS rewrites pointing to 100.110.100.1 / 192.168.1.160.

Tailscale Integration: Tailscale Admin Console Global Nameservers point to AdGuard Home IP with Override local DNS enabled. Linux nodes run tailscale up --accept-dns --ssh.

CoreDNS & Cluster Internal DNS
Placement: Pinned strictly to atlantis (nodeSelector: kubernetes.io/hostname: atlantis).

Upstream Forwarding: Configured in coredns-custom.yaml to forward non-cluster queries directly to AdGuard Home (192.168.1.160) to avoid loopback (127.0.0.53) crashes on worker nodes.

Alpine Linux ndots: 1 Rule: All deployments running Alpine Linux or Musl libc (e.g., Apprise, Uptime Kuma) enforce dnsConfig ndots: "1" to prevent 10-second DNS search domain loops.

Authentik Domain-Level ForwardAuth
Placement: Core DB/Redis and traefik are pinned to atlantis to eliminate cross-node DB latency.

Proxy Provider: Mode: ForwardAuth (domain level) | Cookie Domain: nexus.link (or aura).

In-Namespace Middlewares: Deployed cleanly in respective namespaces (forwardauth-middleware-media.yaml, forwardauth-middleware-monitoring.yaml).

## 4. GitOps Repository Hierarchy & Secrets Architecture
The cluster utilizes a strict separation between version-controlled GitOps manifests ("App of Apps" pattern) and out-of-band secret storage.

### A. Non-Versioned Secrets Directory (~/Elysium-essentials/)
Stored on atlantis outside of Git to prevent credential leaks:

Plaintext
~/Elysium-essentials/
├── RESTIC_MASTER_PASSWORD.txt    # Encryption key for Restic backups
├── ai-secrets.yaml               # LiteLLM/Open-WebUI API tokens
└── argocd-repo-secret.yaml       # ArgoCD GitHub SSH Private Key mapping
B. Versioned GitOps Directory (~/Elysium/)
Plaintext
~/Elysium/
├── app-code/                     # 1. RAW APPLICATION MANIFESTS
│   ├── adguard/                  # DNS & Adblocking
│   ├── apprise/                  # Universal Notification Gateway
│   ├── authentik/                # SSO, Middlewares, CoreDNS tweaks
│   ├── backups/                  # Restic cronjobs & storage
│   ├── bazarr/                   # Subtitle Manager
│   ├── beszel/                   # Lightweight monitoring hub & agents
│   ├── browser/                  # Isolated web browser container
│   ├── filebrowser/              # Web-based file management
│   ├── glances/                  # Node hardware telemetry (Multi-arch DaemonSet)
│   ├── healthchecks/             # Node pingers
│   ├── homarr/                   # Main Service Dashboard
│   ├── homeassistant/            # Smart Home Hub
│   ├── jellyfin/                 # Media Server
│   ├── jellyseerr/               # Media Request Engine
│   ├── lidarr/                   # Music Indexer
│   ├── litellm/                  # AI Model Proxy
│   ├── local-sharing/            # Network file drop
│   ├── n8n/                      # Automation & Workflow Engine
│   ├── netdata/                  # Real-time infrastructure monitoring
│   ├── open-webui/               # Chat Interface for AI models
│   ├── prowlarr/                 # Indexer Coordinator
│   ├── qbittorrent/              # Download Client + VPN Sidecar
│   ├── radarr/                   # Movie Management
│   ├── routing/                  # ArgoCD Ingress
│   ├── scrutiny/                 # Hard Drive S.M.A.R.T. Monitoring
│   ├── sonarr/                   # TV Show Management
│   ├── speedtest-tracker/        # Network speed logging
│   ├── stream/                   # FFmpeg transcoders (sidecam, sjcam, youtube)
│   ├── trawl/                    # FlareSolverr Anti-bot bypass
│   ├── ttyd/                     # Web-based terminal access
│   ├── uptimekuma/               # Uptime monitoring
│   └── whisparr/                 # Adult content indexer
│
├── argocd-apps/                  # 2. ARGOCD WRAPPERS ("App of Apps")
│   ├── adguard-app.yaml
│   ├── apprise-app.yaml
│   ├── backups-app.yaml
│   ├── ... (Matches app-code 1:1)
│
├── cluster-init/                 # 3. NODE BOOTSTRAPPING & TELEMETRY
│   ├── nodes/
│   │   ├── hwres_atlantis
│   │   ├── hwres_olympus
│   │   ├── hwres_phantom
│   │   └── hwres_pi
│   └── update_hwres.sh           # SCP/Git push script for hardware logs
│
├── argocd-ingress.yaml
├── cluster-registry.yaml
├── cluster_ports.md
├── elysium_chat_import.json
└── elysium_cluster_spec.md

## 5. Workload Security & Pod Scheduling Policies
Standardized Security Context
Uses native pod-level unconfined contexts across standard pods (Kubernetes v1.36+):

YAML
securityContext:
  seccompProfile:
    type: Unconfined
  appArmorProfile:
    type: Unconfined
Pod Placement Rules
Control Plane Core (atlantis): SQLite/Database apps, CoreDNS, ArgoCD Stack, Security Stack, Routing, Storage Management.

Stateless Compute & Processing (phantom / olympus / avalon): Apprise (weighted affinity), FlareSolverr/Trawl.

DaemonSets (glances): Multi-arch deployments targeting all nodes, automatically mapping linux/arm64 for pi and linux/amd64 for standard compute nodes.

