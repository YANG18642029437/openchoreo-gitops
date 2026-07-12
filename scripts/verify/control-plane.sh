#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

application=clusters/homelab/applications/14-openchoreo-control-plane.yaml
values=platform/openchoreo/control-plane-values.yaml

test -f "$application" || { echo "missing Control Plane Application" >&2; exit 1; }
test -f "$values" || { echo "missing Control Plane values" >&2; exit 1; }

grep -q 'ghcr.io/openchoreo/helm-charts' "$application"
grep -q 'targetRevision: 1.1.2' "$application"
grep -q 'control-plane-values.yaml' "$application"
grep -q '14-openchoreo-control-plane.yaml' clusters/homelab/kustomization.yaml

grep -q 'api.openchoreo.home.arpa' "$values"
grep -q 'openchoreo.home.arpa' "$values"
grep -q 'thunder.openchoreo.home.arpa' "$values"
grep -q 'thunder-service.thunder.svc.cluster.local:8090/oauth2/jwks' "$values"
grep -q 'metallb.io/loadBalancerIPs: 192.168.2.158' "$values"
grep -q 'secretName: backstage-secrets' "$values"
grep -q 'storageClassName: local-path' "$values"
grep -A1 'group: openchoreo.dev' clusters/homelab/project.yaml | grep -q 'kind: ClusterAuthzRole'
grep -A3 'group: openchoreo.dev' clusters/homelab/project.yaml | grep -q 'kind: ClusterAuthzRoleBinding'

helm template openchoreo-control-plane \
  oci://ghcr.io/openchoreo/helm-charts/openchoreo-control-plane \
  --version 1.1.2 \
  --namespace openchoreo-control-plane \
  --values "$values" >/dev/null

echo 'OpenChoreo Control Plane contract: PASS'
