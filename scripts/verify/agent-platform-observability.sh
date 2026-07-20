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
test "$(grep -c 'enableServiceLinks: false' "$langfuse")" -ge 4
grep -Fq 'bootstrapRevision:' "$langfuse"
grep -Fq 'bootstrapRevision: v4' "$project_base/resources.yaml"
grep -Fq 'printf "DO \$\$ BEGIN' "$langfuse"
grep -Fq 'langfuse_shadow' "$langfuse"
grep -Fq 'name: SHADOW_DATABASE_URL' "$langfuse"
if grep -Eq '(^|[[:space:]])(postgresql|redis|clickhouse|minio)[[:space:]]*:[[:space:]]*enabled' "$langfuse"; then
  printf 'Langfuse ResourceType must not deploy built-in dependencies\n' >&2
  exit 1
fi

test "$(grep -c '^kind: Resource$' "$project_base/resources.yaml")" -eq 8
binding_count="$(grep -c '^kind: ResourceReleaseBinding$' "$project_base/resource-bindings.yaml")"
if [[ "$binding_count" != 5 && "$binding_count" != 8 ]]; then
  printf 'expected either 5 bootstrap bindings or 8 fully pinned bindings, got %s\n' "$binding_count" >&2
  exit 1
fi
for resource in clickhouse langfuse langfuse-retention; do
  grep -Fq "name: ${resource}" "$project_base/resources.yaml"
done
if [[ "$binding_count" == 8 ]]; then
  for resource in clickhouse langfuse langfuse-retention; do
    grep -Fq "name: ${resource}-development" "$project_base/resource-bindings.yaml"
  done
fi

printf 'Agent Platform Langfuse observability contract: PASS\n'
