#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

application=clusters/homelab/applications/15-openchoreo-data-plane.yaml
values=platform/openchoreo/data-plane-values.yaml
bootstrap=scripts/operations/register-data-plane.sh

test -f "$application" || { echo "missing Data Plane Application" >&2; exit 1; }
test -f "$values" || { echo "missing Data Plane values" >&2; exit 1; }
test -x "$bootstrap" || { echo "missing executable Data Plane registration script" >&2; exit 1; }

grep -q 'openchoreo-data-plane' "$application"
grep -q 'targetRevision: 1.1.2' "$application"
grep -q 'sync-wave: "20"' "$application"
grep -q '15-openchoreo-data-plane.yaml' clusters/homelab/kustomization.yaml
grep -q 'metallb.io/loadBalancerIPs: 192.168.2.156' "$values"
grep -q 'planeID: default' "$values"
grep -q 'serverUrl: wss://cluster-gateway.openchoreo-control-plane.svc.cluster.local:8443/ws' "$values"
grep -q 'kind: ClusterDataPlane' "$bootstrap"
grep -q 'name: openbao' "$bootstrap"

helm template openchoreo-data-plane \
  oci://ghcr.io/openchoreo/helm-charts/openchoreo-data-plane \
  --version 1.1.2 \
  --namespace openchoreo-data-plane \
  --values "$values" >/dev/null

echo 'OpenChoreo Data Plane contract: PASS'
