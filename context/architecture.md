# Elysium K3s Cluster Architecture

## Structural Blueprint
- **GitOps Management:** ArgoCD App-of-Apps pattern using wrapper manifests in `argocd-apps/` targeting `app-code/`.
- **Ingress & Authentication:** Traefik Ingress Controller paired with Authentik ForwardAuth middlewares (`*.nexus.link`, `*.aura`).
- **Storage Strategy:** MergerFS volume pools (`/mnt/nexus_pool`) combined with persistent local appdata directories (`/mnt/internal/appdata/`).
- **Node Monitoring:** Glances DaemonSet, Netdata, Scrutiny (S.M.A.R.T.), and Beszel agents feeding hardware statistics back into `cluster-init/nodes/`.

## Non-Versioned Essentials Mapping
- `~/Elysium-essentials/RESTIC_MASTER_PASSWORD.txt` -> Backup encryption keys
- `~/Elysium-essentials/ai-secrets.yaml` -> LiteLLM / Open-WebUI API tokens
- `~/Elysium-essentials/argocd-repo-secret.yaml` -> ArgoCD SSH Key mapping
