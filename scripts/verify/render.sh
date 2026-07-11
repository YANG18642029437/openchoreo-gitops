#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

required=(
  bootstrap/root-application.yaml
  clusters/homelab/kustomization.yaml
  clusters/homelab/project.yaml
)

for path in "${required[@]}"; do
  test -f "$path" || {
    printf 'missing GitOps file: %s\n' "$path" >&2
    exit 1
  }
done

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

kustomize build clusters/homelab >"$rendered"
kubectl apply --dry-run=client -f "$rendered" >/dev/null
printf 'gitops render: PASS\n'
