#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

base=platform/openchoreo/agent-platform
required=(
  "$base/namespace.yaml"
  "$base/environment-development.yaml"
  "$base/deployment-pipeline.yaml"
  "$base/project.yaml"
  "$base/kustomization.yaml"
  clusters/homelab/applications/24-agent-platform.yaml
)

for file in "${required[@]}"; do
  test -f "$file" || {
    printf 'missing Agent Platform control-plane file: %s\n' "$file" >&2
    exit 1
  }
done

/usr/bin/grep -Fq 'name: agent-platform' "$base/namespace.yaml"
/usr/bin/grep -Fq 'openchoreo.dev/control-plane: "true"' "$base/namespace.yaml"
/usr/bin/grep -Fq 'name: development' "$base/environment-development.yaml"
/usr/bin/grep -Fq 'namespace: agent-platform' "$base/environment-development.yaml"
/usr/bin/grep -Fq 'isProduction: false' "$base/environment-development.yaml"
/usr/bin/grep -Fq 'name: development-only' "$base/deployment-pipeline.yaml"
/usr/bin/grep -Fq 'promotionPaths:' "$base/deployment-pipeline.yaml"
/usr/bin/grep -Fq 'targetEnvironmentRefs: []' "$base/deployment-pipeline.yaml"
/usr/bin/grep -Fq 'name: development-only' "$base/project.yaml"
/usr/bin/grep -Fq 'path: platform/openchoreo/agent-platform' \
  clusters/homelab/applications/24-agent-platform.yaml
/usr/bin/grep -Fq 'argocd.argoproj.io/sync-wave: "70"' \
  clusters/homelab/applications/24-agent-platform.yaml
/usr/bin/grep -Fq -- '- applications/24-agent-platform.yaml' \
  clusters/homelab/kustomization.yaml

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
kustomize build "$base" >"$rendered"
kubectl apply --dry-run=client -f "$rendered" >/dev/null
kustomize build clusters/homelab >/dev/null
printf 'Agent Platform control-plane contract: PASS\n'
