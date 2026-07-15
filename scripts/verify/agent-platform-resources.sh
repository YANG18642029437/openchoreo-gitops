#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

types_base=platform/openchoreo/resources
project_base=platform/openchoreo/agent-platform
required=(
  "$types_base/cluster-resource-type-minio.yaml"
  "$types_base/cluster-resource-type-rabbitmq.yaml"
  "$types_base/cluster-resource-type-milvus.yaml"
  "$project_base/resources.yaml"
  "$project_base/resource-bindings.yaml"
)

for file in "${required[@]}"; do
  test -f "$file" || {
    printf 'missing Agent Platform managed resource file: %s\n' "$file" >&2
    exit 1
  }
done

grep -Fq 'name: minio' "$types_base/cluster-resource-type-minio.yaml"
grep -Fq 'quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z' "$types_base/cluster-resource-type-minio.yaml"
grep -Fq 'quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z' "$types_base/cluster-resource-type-minio.yaml"
grep -Fq 'secretPath: agent-platform/development/minio' "$project_base/resources.yaml"
grep -Fq 'rabbitmq:4.2.6-management' "$types_base/cluster-resource-type-rabbitmq.yaml"
grep -Fq 'milvusdb/milvus:v2.6.16' "$types_base/cluster-resource-type-milvus.yaml"
test "$(grep -c '^kind: Resource$' "$project_base/resources.yaml")" -eq 3
test "$(grep -c '^kind: ResourceReleaseBinding$' "$project_base/resource-bindings.yaml")" -eq 3
test "$(grep -c 'retainPolicy: Retain' "$project_base/resource-bindings.yaml")" -eq 3

rendered="$(mktemp "${TMPDIR:-/tmp}/agent-platform-resources.XXXXXX")"
trap 'rm -f "$rendered"' EXIT

kustomize build "$types_base" >"$rendered"
kubectl apply --server-side --dry-run=server -f "$rendered" >/dev/null
kustomize build "$project_base" >"$rendered"
kubectl apply --server-side --dry-run=server -f "$rendered" >/dev/null

printf 'Agent Platform managed resources contract: PASS\n'
