# Elysium K3s Cluster Prompt Context

## Node Topology
- **atlantis** (`192.168.1.160`): Control Plane, Traefik Ingress, Authentik SSO, Core Databases, Storage Host.
- **olympus** (`192.168.1.243`): Compute Worker Node.
- **phantom** (`192.168.1.170`): Compute Worker Node.
- **pi** (`192.168.1.130`): Cordoned/Tainted (armv7l 32-bit architecture).

## Code Base Layout
- `app-code/`: Raw Kubernetes manifests organized per application.
- `argocd-apps/`: ArgoCD App-of-Apps wrapper definitions matching `app-code/` 1:1.
- `context/`: Source-of-truth files for AI guidance (`architecture.md`, `context.md`, `state.md`).

## Core Rules for AI Code Generation
1. Persistent data must map to `/mnt/internal/appdata/<app_name>` on `atlantis`.
2. Apply `seccompProfile: Unconfined` and `appArmorProfile: Unconfined` to PodSpecs for K8s 1.36+ compatibility.
3. Secrets are managed out-of-band in `~/Elysium-essentials/` (do not hardcode plain secrets).
4. Reference `cluster_ports.md` before binding hostPorts to avoid network collisions.
