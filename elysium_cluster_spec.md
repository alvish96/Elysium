# Elysium K3s Cluster Master Specification

## Cluster Topology
- Control Plane: atlantis (192.168.1.160)
- Workers: avalon, phantom (192.168.1.170), olympus, pi
- Repository: git@github.com:alvish96/Elysium.git (ArgoCD SSH Key: /root/.ssh/id_ed25519)

## Media Stack & Ports
- Jellyfin: http://192.168.1.160:30096
- Prowlarr: http://192.168.1.160:30396
- qBittorrent + Gluetun Proxy: Proxy host `qbittorrent-svc` on port 8888
- FlareSolverr: `http://flaresolverr-svc:8191`
- Trawl: Stateless failover on avalon -> phantom on port 8191
