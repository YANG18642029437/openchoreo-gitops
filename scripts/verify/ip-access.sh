#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

root=infrastructure/ip-access
required=(
  "$root/namespace.yaml"
  "$root/configmap.yaml"
  "$root/certificate.yaml"
  "$root/deployment.yaml"
  "$root/service.yaml"
  "$root/network-policy.yaml"
  "$root/kustomization.yaml"
  clusters/homelab/applications/27-ip-access.yaml
)
for file in "${required[@]}"; do
  test -f "$file" || { printf 'missing IP access file: %s\n' "$file" >&2; exit 1; }
done

grep -q 'namespace: platform-access' "$root/certificate.yaml"
grep -q 'name: homelab-root-ca' "$root/certificate.yaml"
grep -A2 'ipAddresses:' "$root/certificate.yaml" | grep -q '192.168.2.154'
grep -q 'replicas: 2' "$root/deployment.yaml"
grep -q 'podAntiAffinity:' "$root/deployment.yaml"
grep -Eq 'image: harbor\.openchoreo\.home\.arpa/openchoreo/ip-access-nginx@sha256:[a-f0-9]{64}' "$root/deployment.yaml"
grep -q 'runAsNonRoot: true' "$root/deployment.yaml"
grep -q 'readOnlyRootFilesystem: true' "$root/deployment.yaml"
grep -q 'type: LoadBalancer' "$root/service.yaml"
grep -q 'metallb.io/loadBalancerIPs: 192.168.2.154' "$root/service.yaml"
grep -A2 'loadBalancerSourceRanges:' "$root/service.yaml" | grep -q '192.168.1.108/32'
grep -q 'allocateLoadBalancerNodePorts: false' "$root/service.yaml"
grep -q 'externalTrafficPolicy: Cluster' "$root/service.yaml"
for port in 31001 31002 31003 31004 31005 31006 31007; do
  grep -q "port: $port" "$root/service.yaml"
done
for host in argocd harbor openbao observer thunder; do
  grep -q "$host.openchoreo.home.arpa" "$root/configmap.yaml"
done
grep -q 'openchoreo.home.arpa' "$root/configmap.yaml"
grep -q 'http://thunder.openchoreo.home.arpa:80/' "$root/configmap.yaml"
grep -q 'http://openchoreo.home.arpa:80/' "$root/configmap.yaml"
sed -n '/listen 8446/,/^      }/p' "$root/configmap.yaml" | grep -q "sub_filter 'http://thunder.openchoreo.home.arpa'"
grep -q 'location = /gate/config.js' "$root/configmap.yaml"
grep -q 'Cache-Control "no-store"' "$root/configmap.yaml"
sed -n '/listen 8446/,/^      }/p' "$root/configmap.yaml" | grep -q 'sub_filter_types application/javascript text/javascript application/json'
grep -q 'listen 8447 ssl' "$root/configmap.yaml"
grep -q 'langfuse.dp-agent-platfor-agent-platfor-development-4e4bdc7d.svc.cluster.local:3000' "$root/configmap.yaml"
grep -q 'name: langfuse' "$root/deployment.yaml"
grep -q 'containerPort: 8447' "$root/deployment.yaml"
grep -q 'targetPort: langfuse' "$root/service.yaml"
grep -q 'dp-agent-platfor-agent-platfor-development-4e4bdc7d' "$root/network-policy.yaml"
grep -q 'port: 3000' "$root/network-policy.yaml"
grep -q 'Upgrade' "$root/configmap.yaml"
grep -q 'kind: NetworkPolicy' "$root/network-policy.yaml"
grep -q 'port: 8080' "$root/network-policy.yaml"
grep -q 'path: infrastructure/ip-access' clusters/homelab/applications/27-ip-access.yaml
grep -q 'targetRevision: main' clusters/homelab/applications/27-ip-access.yaml

if rg -n 'externalTrafficPolicy: Local|^[[:space:]]+loadBalancerIP:|type: NodePort|nodePort:|Access-Control-Allow-Origin:[[:space:]]*\*|redirect.*\*' "$root"; then
  printf 'IP access safety contract violation\n' >&2
  exit 1
fi

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
kubectl kustomize "$root" >"$rendered"
kubectl apply --dry-run=client -f "$rendered" >/dev/null
if kubectl get namespace platform-access >/dev/null 2>&1; then
  kubectl apply --dry-run=server -f "$rendered" >/dev/null
else
  kubectl apply --dry-run=server -f "$root/namespace.yaml" >/dev/null
fi

printf 'IP port Web access contract: PASS\n'
