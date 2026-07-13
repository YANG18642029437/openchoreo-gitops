#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

application=clusters/homelab/applications/16-openchoreo-workflow-plane.yaml
values=platform/openchoreo/workflow-plane-values.yaml
runtime=platform/openchoreo/workflow-runtime/namespace.yaml
bootstrap=scripts/operations/register-workflow-plane.sh

test -f "$application" || { echo "missing Workflow Plane Application" >&2; exit 1; }
test -f "$values" || { echo "missing Workflow Plane values" >&2; exit 1; }
test -f "$runtime" || { echo "missing argo-build namespace manifest" >&2; exit 1; }
test -x "$bootstrap" || { echo "missing executable Workflow Plane registration script" >&2; exit 1; }

grep -q 'openchoreo-workflow-plane' "$application"
grep -q 'targetRevision: 1.1.2' "$application"
grep -q 'sync-wave: "30"' "$application"
grep -q 'workflow-runtime' "$application"
grep -q 'managedFieldsManagers' "$application"
grep -q 'kube-apiserver' "$application"
grep -q '16-openchoreo-workflow-plane.yaml' clusters/homelab/kustomization.yaml
grep -q 'serverUrl: wss://cluster-gateway.openchoreo-control-plane.svc.cluster.local:8443/ws' "$values"
grep -q 'planeID: default' "$values"
grep -A2 'server:' "$values" | grep -q 'enabled: false'
grep -q 'name: argo-build' "$runtime"
grep -q 'kind: ClusterWorkflowPlane' "$bootstrap"
grep -q 'name: openbao' "$bootstrap"

helm template openchoreo-workflow-plane \
  oci://ghcr.io/openchoreo/helm-charts/openchoreo-workflow-plane \
  --version 1.1.2 \
  --namespace openchoreo-workflow-plane \
  --values "$values" >/dev/null

echo 'OpenChoreo Workflow Plane contract: PASS'
