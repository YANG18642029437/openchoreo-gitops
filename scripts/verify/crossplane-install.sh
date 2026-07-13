#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

crossplane_app=clusters/homelab/applications/21-crossplane.yaml
cnpg_app=clusters/homelab/applications/22-cloudnative-pg.yaml
project=clusters/homelab/project.yaml
cluster_kustomization=clusters/homelab/kustomization.yaml

required=(
  "$crossplane_app"
  "$cnpg_app"
  platform/crossplane/kustomization.yaml
  platform/crossplane/providers.yaml
  platform/cloudnative-pg/kustomization.yaml
)

for path in "${required[@]}"; do
  test -f "$path" || {
    printf 'missing Phase 05 install file: %s\n' "$path" >&2
    exit 1
  }
done

grep -q 'repoURL: https://charts.crossplane.io/stable' "$crossplane_app"
grep -q 'targetRevision: 2.3.3' "$crossplane_app"
grep -q 'replicas: 2' "$crossplane_app"
grep -q 'rbacManager:' "$crossplane_app"
grep -A2 'rbacManager:' "$crossplane_app" | grep -q 'replicas: 2'
grep -q 'kubernetes.io/hostname' "$crossplane_app"

grep -q 'repoURL: ghcr.io/cloudnative-pg/charts' "$cnpg_app"
grep -q 'targetRevision: 0.29.0' "$cnpg_app"
grep -q 'replicaCount: 2' "$cnpg_app"
grep -q 'kubernetes.io/hostname' "$cnpg_app"

grep -q 'https://charts.crossplane.io/stable' "$project"
grep -q 'ghcr.io/cloudnative-pg/charts' "$project"
grep -q 'applications/21-crossplane.yaml' "$cluster_kustomization"
grep -q 'applications/22-cloudnative-pg.yaml' "$cluster_kustomization"

kustomize build platform/crossplane >/dev/null
kustomize build platform/cloudnative-pg >/dev/null
kustomize build clusters/homelab >/dev/null

if rg -ni 'proxmox|terraform' platform/crossplane "$crossplane_app"; then
  printf 'Phase 05 Crossplane scope violation: Proxmox and Terraform remain outside Crossplane\n' >&2
  exit 1
fi

printf 'Phase 05 controller install contract: PASS\n'
