# FortiVPN Runbook: Deployment, Connectivity Verification & SSH Access

This runbook outlines the operational lifecycle of the containerized FortiClient SSL-VPN (`openfortivpn`) running in the `networking` namespace on node `atlantis`. It provides commands to initiate the deployment, verify connectivity, restart the pod upon failures, check tunnel routing, and execute SSH sessions into remote target IP addresses (e.g., `10.25.117.173`).

---

## 1. Initiate / Deploy the FortiVPN Pod

The FortiVPN setup consists of two primary components:
1. `~/Elysium-essentials/fortivpn-secret.yaml` (VPN Gateway credentials & certificate whitelist).
2. `~/Elysium/app-code/fortivpn/fortivpn.yaml` (Deployment & NodePort Service).

### Step 1.1: Verify Secret Presence
Ensure the required secret exists in the `networking` namespace:
```bash
kubectl get secret -n networking fortivpn-secret
```

### Step 1.2: Deploy Manifest
Apply the workload manifest to initiate or update the deployment:
```bash
kubectl apply -f ~/Elysium/app-code/fortivpn/fortivpn.yaml
```

### Step 1.3: Confirm Pod Running State
Verify the pod transitions to `2/2 Running` on node `atlantis`:
```bash
kubectl get pods -n networking -l app=fortivpn -o wide
```
* **Expected Output:**
  * Pod status: `Running`
  * Ready: `2/2`
  * Node: `atlantis`

---

## 2. Check VPN Tunnel Connectivity & Interface Status

### Step 2.1: Check Tunnel Connection Logs
Inspect the initialization and SSL-VPN negotiation logs:
```bash
kubectl logs -n networking deployment/fortivpn -c fortivpn --tail=30
```
* **Healthy Signatures:**
  ```text
  INFO: Connected to gateway.
  INFO: Authenticated.
  INFO: Remote gateway has allocated a VPN.
  Using interface ppp0
  INFO: Interface ppp0 is UP.
  INFO: Setting new routes...
  INFO: Adding VPN nameservers...
  INFO: Tunnel is up and running.
  ```

### Step 2.2: Verify the Tunnel Interface (`ppp0`)
Inspect the virtual point-to-point interface inside the container:
```bash
kubectl exec -it -n networking deployment/fortivpn -c fortivpn -- ip addr show ppp0
```
* **Expected Output:**
  ```text
  4: ppp0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1354 ...
      inet 172.16.25.2 peer 169.254.2.1/32 scope global ppp0
  ```

### Step 2.3: Check Kernel Route Allocation
Ensure the remote network subnets are bound to `ppp0` inside the container:
```bash
# View active routes pushed by the FortiGate
kubectl exec -it -n networking deployment/fortivpn -c fortivpn -- ip route

# Verify specific destination route evaluation (e.g., 10.25.117.173)
kubectl exec -it -n networking deployment/fortivpn -c fortivpn -- ip route get 10.25.117.173
```
* **Expected Route Result:**
  ```text
  10.25.117.173 dev ppp0 src 172.16.25.2 uid 0
  ```

### Step 2.4: Verify Host Isolation (Safety Check)
Confirm that the host `atlantis` routing table remains untouched:
```bash
ip addr show ppp0
```
* **Expected Output:** `Device "ppp0" does not exist.`

---

## 3. Pod Restart & Recovery Procedures

If the tunnel drops, enters an unrecoverable state, or requires reconfiguration, use the following operational procedures:

### Option A: Clean Rolling Restart
Trigger a graceful restart of the deployment:
```bash
kubectl rollout restart deployment/fortivpn -n networking
```

### Option B: Immediate Hard Recreation (Force Kill)
If the container process hangs or fails to terminate cleanly:
```bash
kubectl delete pod -n networking -l app=fortivpn --force --grace-period=0
```

### Option C: Monitor Pod Recovery
Watch the pod terminate and re-initialize in real time:
```bash
kubectl get pods -n networking -l app=fortivpn -w
```

---

## 4. SSH into the Target Remote Machine (Method 2: Atlantis CLI)

### Step 4.1: Ensure OpenSSH Client & Diagnostic Tools are Installed
Verify or install necessary networking binaries inside the running container:
```bash
# Check existing binaries
kubectl exec -it -n networking deployment/fortivpn -c fortivpn -- which ssh ping || kubectl exec -it -n networking deployment/fortivpn -c fortivpn -- bash -c   "apt-get update && apt-get install -y openssh-client iputils-ping"
```

### Step 4.2: Direct Interactive SSH Execution (Password Auth)
Execute the SSH command directly from the `atlantis` shell through the pod's container:
```bash
kubectl exec -it -n networking deployment/fortivpn -c fortivpn -- ssh admin@10.25.117.173
```
* When prompted for key fingerprint confirmation, type `yes`.
* Enter the remote password when requested.

### Step 4.3: Direct SSH Execution Using Atlantis Private Key
To pass an existing SSH private key from `atlantis` into the target session:
```bash
# 1. Identify active pod
POD_NAME=$(kubectl get pods -n networking -l app=fortivpn -o jsonpath='{.items[0].metadata.name}')

# 2. Copy the key into the pod's ephemeral /tmp storage
kubectl cp ~/.ssh/id_rsa networking/${POD_NAME}:/tmp/id_rsa -c fortivpn
kubectl exec -it -n networking deployment/fortivpn -c fortivpn -- chmod 600 /tmp/id_rsa

# 3. SSH specifying the private identity file
kubectl exec -it -n networking deployment/fortivpn -c fortivpn -- ssh -i /tmp/id_rsa admin@10.25.117.173

# 4. Clean up key after session completion
kubectl exec -it -n networking deployment/fortivpn -c fortivpn -- rm -f /tmp/id_rsa
```

### Step 4.4: Full Interactive Container Shell
If you need an interactive terminal session inside the container environment to run diagnostic tools and SSH commands sequentially:
```bash
kubectl exec -it -n networking deployment/fortivpn -c fortivpn -- /bin/bash
```
Inside the container prompt:
```bash
# Run tests and connect
ping -c 3 10.25.117.173
ssh admin@10.25.117.173

# Exit container prompt back to atlantis
exit
```

---

## 5. Troubleshooting Reference

| Issue / Error | Cause | Remediation |
| :--- | :--- | :--- |
| `Device "ppp0" does not exist` inside pod | OpenFortiVPN process failed or crashed | Run `kubectl logs -n networking deployment/fortivpn -c fortivpn --tail=50` to inspect error logs. |
| `exec: "ping": executable file not found in $PATH` | `iputils-ping` package not in container image | Install inside container: `kubectl exec -it -n networking deployment/fortivpn -c fortivpn -- apt-get update && apt-get install -y iputils-ping`. |
| `Network is unreachable` on ping/SSH | Target IP is not routed through `ppp0` | Check routing table via `kubectl exec -it -n networking deployment/fortivpn -c fortivpn -- ip route`. |
| `Permission denied, please try again` | Incorrect remote password or user | Verify remote host credentials for the target server (`admin@10.25.117.173`). |
