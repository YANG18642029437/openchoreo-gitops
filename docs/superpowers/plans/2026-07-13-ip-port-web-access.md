# IP Port Web Access Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a private, HTTPS-only gateway at `192.168.2.154:31001-31006` for the six approved Web management platforms without exposing internal platform services.

**Architecture:** A two-replica unprivileged Nginx deployment terminates an internal-CA IP certificate and assigns one listener to each platform. A MetalLB LoadBalancer Service publishes the fixed address and source-restricts it to the Mac; each listener forwards through the existing Ingress or Gateway API route with the canonical Host header.

**Tech Stack:** Kubernetes, Kustomize, Argo CD, MetalLB, cert-manager, Cilium NetworkPolicy, Nginx unprivileged, Bash verification, Harbor OCI registry

---

### Task 1: Preflight and contract test

**Files:**
- Create: `scripts/verify/ip-access.sh`

- [ ] **Step 1: Write the failing static contract**

Create a strict Bash verifier that requires `infrastructure/ip-access/{namespace,configmap,certificate,deployment,service,network-policy,kustomization}.yaml` and `clusters/homelab/applications/27-ip-access.yaml`. It must assert the IP, all six ports, `loadBalancerSourceRanges: 192.168.31.97/32`, two replicas, anti-affinity, IP SAN certificate, no NodePort, no wildcard redirect/CORS, and a digest-pinned Harbor image.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
./scripts/verify/ip-access.sh
```

Expected: non-zero with `missing IP access file`.

- [ ] **Step 3: Perform read-only address and source preflight**

Run:

```bash
ping -c 2 -W 1000 192.168.2.154
arp -an | grep '192.168.2.154'
kubectl -n metallb-system get ipaddresspool homelab -o yaml
kubectl get service -A -o wide | grep '192.168.2.154'
```

Expected: no ping/ARP/Service owner for `.154`, and the MetalLB pool includes it. Any positive owner stops implementation.

- [ ] **Step 4: Commit the RED contract**

```bash
git add scripts/verify/ip-access.sh
git commit -m "test: define IP access gateway contract"
```

### Task 2: Mirror the pinned proxy image

**Files:**
- Modify later: `infrastructure/ip-access/deployment.yaml`

- [ ] **Step 1: Pull a fixed unprivileged image**

```bash
docker pull nginxinc/nginx-unprivileged:1.29.3-alpine
```

Expected: image pull succeeds.

- [ ] **Step 2: Mirror into Harbor**

Load Harbor credentials from `../openchoreo-infra/.private/openbao/harbor.env` without printing them, log in with `--password-stdin`, then run:

```bash
docker tag nginxinc/nginx-unprivileged:1.29.3-alpine \
  harbor.openchoreo.home.arpa/openchoreo/ip-access-nginx:1.29.3-alpine
docker push harbor.openchoreo.home.arpa/openchoreo/ip-access-nginx:1.29.3-alpine
docker inspect --format='{{json .RepoDigests}}' \
  harbor.openchoreo.home.arpa/openchoreo/ip-access-nginx:1.29.3-alpine
```

Expected: Harbor returns a `sha256:` digest. The deployment must use the Harbor repository plus that digest, never the tag alone.

### Task 3: Implement the access gateway

**Files:**
- Create: `infrastructure/ip-access/namespace.yaml`
- Create: `infrastructure/ip-access/configmap.yaml`
- Create: `infrastructure/ip-access/certificate.yaml`
- Create: `infrastructure/ip-access/deployment.yaml`
- Create: `infrastructure/ip-access/service.yaml`
- Create: `infrastructure/ip-access/network-policy.yaml`
- Create: `infrastructure/ip-access/kustomization.yaml`

- [ ] **Step 1: Add namespace and certificate**

Create namespace `platform-access` and Certificate `ip-access-tls` using ClusterIssuer `homelab-root-ca`, secret `ip-access-tls`, and:

```yaml
ipAddresses:
  - 192.168.2.154
```

- [ ] **Step 2: Add six TLS proxy listeners**

The ConfigMap must define listeners `8441-8446`, load `/etc/nginx/tls/tls.crt` and `tls.key`, use HTTP/1.1 and Upgrade headers, suppress credential-bearing access fields, and route as follows:

```text
8441 -> https://argocd-server.argocd.svc.cluster.local:443                 Host argocd.openchoreo.home.arpa
8442 -> https://ingress-nginx-controller.ingress-nginx.svc.cluster.local:443 Host harbor.openchoreo.home.arpa
8443 -> https://ingress-nginx-controller.ingress-nginx.svc.cluster.local:443 Host openbao.openchoreo.home.arpa
8444 -> http://gateway-default.openchoreo-control-plane.svc.cluster.local:80  Host openchoreo.home.arpa
8445 -> http://gateway-default.openchoreo-observability-plane.svc.cluster.local:80 Host observer.openchoreo.home.arpa
8446 -> http://gateway-default.openchoreo-control-plane.svc.cluster.local:80  Host thunder.openchoreo.home.arpa
```

Use explicit `proxy_redirect` rules from each canonical origin to its matching IP-port origin. Permit response substitution only for Backstage runtime app-config JSON on port 31004; do not rewrite JS bundles.

- [ ] **Step 3: Add the two-replica Deployment**

Use the Harbor digest from Task 2, `runAsNonRoot`, read-only root filesystem, dropped capabilities, seccomp RuntimeDefault, 25m/32Mi requests, 250m/128Mi limits, required pod anti-affinity by hostname, and TCP liveness/readiness on 8441. Mount ConfigMap read-only at `/etc/nginx/nginx.conf` and TLS secret read-only at `/etc/nginx/tls`.

- [ ] **Step 4: Add the fixed LoadBalancer Service**

Use:

```yaml
type: LoadBalancer
loadBalancerIP: 192.168.2.154
loadBalancerSourceRanges:
  - 192.168.31.97/32
```

Map external ports `31001-31006` to target ports `8441-8446`; do not set `nodePort` and disable automatic node-port allocation if supported by the installed Kubernetes API.

- [ ] **Step 5: Add least-privilege NetworkPolicy**

Default deny ingress and egress. Allow ingress only on 8441-8446. Allow egress UDP/TCP 53 to kube-dns and TCP 80/443/8200 only to namespaces `argocd`, `ingress-nginx`, `openchoreo-control-plane`, and `openchoreo-observability-plane` selected by `kubernetes.io/metadata.name`.

- [ ] **Step 6: Render and make the contract GREEN**

```bash
kubectl kustomize infrastructure/ip-access >/tmp/ip-access.yaml
kubectl apply --dry-run=server -f /tmp/ip-access.yaml
./scripts/verify/ip-access.sh
```

Expected: server dry-run and contract both PASS.

- [ ] **Step 7: Commit gateway resources**

```bash
git add infrastructure/ip-access scripts/verify/ip-access.sh
git commit -m "feat: add private IP Web access gateway"
```

### Task 4: Add the Argo CD application and deploy

**Files:**
- Create: `clusters/homelab/applications/27-ip-access.yaml`
- Modify: `clusters/homelab/kustomization.yaml`

- [ ] **Step 1: Add the child Application**

Use project `homelab-platform`, destination namespace `platform-access`, path `infrastructure/ip-access`, sync wave `80`, automated prune/self-heal, and temporary target revision `codex/ip-port-web-access`.

- [ ] **Step 2: Register it in the root Kustomization**

Append `applications/27-ip-access.yaml`, render the root, and rerun `scripts/verify/{render,secrets,ip-access}.sh`.

- [ ] **Step 3: Commit and push the implementation branch**

```bash
git add clusters/homelab
git commit -m "feat: deploy IP access gateway with Argo CD"
git push -u origin codex/ip-port-web-access
```

- [ ] **Step 4: Apply and wait for health**

Apply the Application directly only to bootstrap branch tracking, then wait for Application `ip-access` to become Synced/Healthy, Certificate Ready, Deployment 2/2 and LoadBalancer external IP `.154`.

- [ ] **Step 5: Confirm the observed Mac source address**

Call one endpoint from the Mac. If source restriction rejects it, capture only packet source metadata on the announcing node, update the single `/32` to the observed routed/NAT address, and retest. Never broaden to a subnet.

### Task 5: Validate all six Web applications

**Files:**
- Create: `scripts/verify/ip-access-live.sh`
- Create: `docs/access/ip-port-web-access.md`

- [ ] **Step 1: Add automated live probes**

Probe all six IP-port URLs without `-k`, require a valid internal-CA chain, accept only documented 2xx/3xx responses, reject canonical-domain redirects, verify certificate IP SAN, and ensure internal ClusterIP services remain unexposed.

- [ ] **Step 2: Verify browser behavior**

Using the logged-in Chrome session, check each port for page load, login, navigation, API calls, redirect loops, Cookie errors and WebSocket failures. For OpenChoreo also validate the Thunder login callback and project/component pages.

- [ ] **Step 3: Validate existing domain entries**

Run the same smoke actions against Argo CD, Harbor, OpenBao, OpenChoreo, Observer and Thunder canonical domains. Expected: no regression.

- [ ] **Step 4: Run node-level availability check**

Delete no resources. Restart one gateway Pod and verify all six endpoints remain available while the Deployment returns to 2/2.

- [ ] **Step 5: Document access and commit**

Document the six URLs, source-IP restriction, CA requirement, troubleshooting and rollback. Then:

```bash
git add scripts/verify/ip-access-live.sh docs/access/ip-port-web-access.md
git commit -m "test: verify IP port Web access"
```

### Task 6: Merge and return GitOps to main

**Files:**
- Modify: `clusters/homelab/applications/27-ip-access.yaml`

- [ ] **Step 1: Run final verification on the branch**

```bash
./scripts/verify/render.sh
./scripts/verify/secrets.sh
./scripts/verify/policies.sh
./scripts/verify/ip-access.sh
./scripts/verify/ip-access-live.sh
```

The policy test is expected to fail only while the child Application intentionally tracks the implementation branch; all other checks must pass.

- [ ] **Step 2: Merge the branch into main and push**

Merge without a worktree, push `main`, change the child Application target revision to `main`, rerun all five verification scripts with zero failures, commit, and push again.

- [ ] **Step 3: Confirm Argo convergence**

Set the runtime child Application to `main`, wait for root and child to be Synced/Healthy, rerun six live probes, and confirm the Git working tree is clean.
