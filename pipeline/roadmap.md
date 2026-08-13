# Project Elysium - Future Roadmap & Feature Pipeline (ROADMAP.md)

## 🎯 Active Strategic Goals

---

### 🟢 Phase 1: Self-Hosted Messaging Platform
- **Goal**: Replace reliance on commercial social media/messaging platforms with a self-hosted, encrypted communication server.
- **Target Application**: Matrix Protocol (**Conduit** lightweight Rust backend + **Element** Web/Mobile Frontend).
- **Architecture Requirements**:
  - Ingress: `chat.nexus.link` (Traefik IngressRoute + Authentik ForwardAuth).
  - Storage: Persistent Volume anchored on `atlantis` SSD (`/mnt/internal/appdata/matrix`).
  - Namespace: `communication`
  - Integration: Matrix bridges for Telegram and Discord notification routing.

---

### 🟢 Phase 2: AI-Powered Idea & Hypothesis Tracker
- **Goal**: Build an automated system that converts quick notes and ideas into structured hypotheses and actionable To-Do items.
- **Core Stack**:
  - **Capture Layer**: Webhook endpoint / Telegram Bot / Discord Channel.
  - **Orchestration Layer**: `n8n` (running in `media` namespace) to parse and route ideas.
  - **AI Extraction Layer**: `LiteLLM` + Open-WebUI model backend for automated categorization and action-item parsing.
  - **Storage & Dashboard Layer**: **Memos** (`usememos/memos`) or **Vikunja** REST API.
  - **Homarr Integration**: Embed dynamic Markdown/iFrame widget directly on `homarr.nexus.link`.

---

### 🟢 Phase 3: Off-Site Failover Test Suite (`hcnvedl1108401`)
- **Goal**: Safely validate stateful NFS and CNI cross-site workloads on the off-site Tailscale node before promoting compute workloads.
- **Execution Strategy**:
  - Keep `hcnvedl1108401` cordoned (`SchedulingDisabled`) for production pods.
  - Build a parallel, non-destructive test suite (`hcn-test-suite`) to benchmark Tailscale MTU clamping and cross-site Flannel performance.

---

## 📌 Implementation Checklist & Tracking

- [ ] Deploy `memos` or `vikunja` to `media` namespace.
- [ ] Create `n8n` workflow: `Webhook Input` -> `LiteLLM System Prompt` -> `Memos API`.
- [ ] Embed Memos REST feed widget into Homarr dashboard.
- [ ] Create `communication` namespace manifest for Matrix Conduit + Element Web.
- [ ] Route `chat.nexus.link` through Traefik and Authentik SSO.
