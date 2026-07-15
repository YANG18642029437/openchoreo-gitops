#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

rbac=platform/openchoreo/data-plane-runtime/resource-operator-rbac.yaml
test -f "$rbac" || {
  printf 'missing Agent Platform resource operator RBAC: %s\n' "$rbac" >&2
  exit 1
}

for contract in \
  'apiGroups: [rabbitmq.com]' \
  'resources: [rabbitmqclusters]' \
  'apiGroups: [milvus.io]' \
  'resources: [milvuses]' \
  'name: cluster-agent-dataplane' \
  'namespace: openchoreo-data-plane'; do
  /usr/bin/grep -Fq "$contract" "$rbac"
done

/usr/bin/grep -Fq -- '- resource-operator-rbac.yaml' \
  platform/openchoreo/data-plane-runtime/kustomization.yaml

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
kustomize build platform/openchoreo/data-plane-runtime >"$rendered"
kubectl apply --server-side --dry-run=server -f "$rendered" >/dev/null
printf 'Agent Platform resource operator RBAC: PASS\n'
