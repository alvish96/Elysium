# Central Network & Port Allocation Matrix

This file tracks all port mapping parameters across the `atlantis` and `phantom` cluster infrastructure. Edit this file whenever assigning new NodePorts, Ingress routes, or local network endpoints.

| Application / Service | Namespace | Service Type | Internal Port | External Exposed Port / Host | Target Node / Placement | Status | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Home Assistant | homeassistant | NodePort | 8123 | 38123 / https://homeassistant.local | Pinned to phantom (Compute Muscle) | Active | Port 38123 explicitly assigned |
| **K3s API Server** | `kube-system` | Native | `6443` | `6443` | `atlantis` (Master) | Active | Core cluster orchestration API endpoint |
| **Traefik Ingress HTTP** | `kube-system` | LoadBalancer | `80` | `80` (via NodePort `31090`) | All Nodes (`192.168.1.160` / `.170`) | Active | Core reverse proxy traffic loop |
| **Traefik Ingress HTTPS**| `kube-system` | LoadBalancer | `443` | `443` (via NodePort `31981`)| All Nodes (`192.168.1.160` / `.170`) | Active | Core secure reverse proxy traffic loop |
| **ArgoCD Server HTTP** | `argocd` | NodePort | `80` | `30173` | All Nodes (`atlantis` / `phantom`) | Active | GitOps Control Plane UI (Unsecure) |
| **ArgoCD Server HTTPS** | `argocd` | NodePort | `443` | `30346` | All Nodes (`atlantis` / `phantom`) | Active | GitOps Control Plane UI (Secure Login) |
| **Jellyfin Service** | `media` | ClusterIP | `8096` | `https://jellyfin.local` | Pinned to `atlantis` (Storage Node) | Active | Routed via Traefik IngressRoute |
| **NFS Share Export** | Host Level | Native OS | `2049` | `2049` | `phantom` -> `atlantis` | Active | Shares unallocated LVM storage space |
| **Home Assistant** | `default` | *Planned* | `8123` | *TBD / 38123* | Pinned to `atlantis` (Battery Backup) | Staged | Smart Home automation suite |
| **Vaultwarden** | `default` | *Planned* | `80` | *TBD / Ingress* | Pinned to `atlantis` (Battery Backup) | Staged | Password credentials repository |
| **Immich Core API** | `media` | *Planned* | `2283` | *TBD / Ingress* | Pinned to `atlantis` (Database State) | Staged | Self-hosted photo management system |
| **Duplicati** | `infra` | *Planned* | `8200` | *TBD / 38200* | Pinned to `atlantis` (Backup Vault) | Staged | Isolated storage scheduler |

## Port Ranges Configuration Reference Policy
- **Standard ClusterIP Range:** Managed dynamically by Kubernetes internal overlay network (`10.43.X.X`).
- **Custom NodePort Allocation Range:** Reserved between `30000` and `32767`.
- **Custom Host Port Rules:** High ports outside Kubernetes limits can be mapped locally via Traefik `IngressRoute` bindings to keep host ports clear.
