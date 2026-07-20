#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

types_base=platform/openchoreo/resources
project_base=platform/openchoreo/agent-platform
clickhouse="$types_base/cluster-resource-type-clickhouse.yaml"
langfuse="$types_base/cluster-resource-type-langfuse.yaml"
retention="$project_base/resource-type-langfuse-retention.yaml"

for file in "$clickhouse" "$langfuse" "$retention"; do
  test -f "$file" || {
    printf 'missing observability resource contract: %s\n' "$file" >&2
    exit 1
  }
done

grep -Fq 'cluster-resource-type-clickhouse.yaml' "$types_base/kustomization.yaml"
grep -Fq 'cluster-resource-type-langfuse.yaml' "$types_base/kustomization.yaml"
grep -Fq 'resource-type-langfuse-retention.yaml' "$project_base/kustomization.yaml"

grep -Eq 'image: .+@sha256:[0-9a-f]{64}' "$clickhouse"
test "$(grep -Ec 'image: .+@sha256:[0-9a-f]{64}' "$langfuse")" -ge 4
grep -Eq 'image: .+@sha256:[0-9a-f]{64}' "$retention"

for file in "$clickhouse" "$langfuse" "$retention"; do
  grep -Fq 'secretKeyRef:' "$file"
  grep -Fq 'readyWhen:' "$file"
done

for dependency in postgresql redis minio clickhouse; do
  grep -Fq "${dependency}" "$langfuse"
done
if grep -Eq '(^|[[:space:]])(postgresql|redis|clickhouse|minio)[[:space:]]*:[[:space:]]*enabled' "$langfuse"; then
  printf 'Langfuse ResourceType must not deploy built-in dependencies\n' >&2
  exit 1
fi

test "$(grep -c '^kind: Resource$' "$project_base/resources.yaml")" -eq 8
test "$(grep -c '^kind: ResourceReleaseBinding$' "$project_base/resource-bindings.yaml")" -eq 8
grep -Fq 'name: clickhouse' "$project_base/resources.yaml"
grep -Fq 'name: langfuse' "$project_base/resources.yaml"
grep -Fq 'name: langfuse-retention' "$project_base/resources.yaml"

printf 'Agent Platform Langfuse observability contract: PASS\n'
