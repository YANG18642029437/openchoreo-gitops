#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

types_base=platform/openchoreo/resources
project_base=platform/openchoreo/agent-platform
required=(
  "$types_base/cluster-resource-type-postgresql.yaml"
  "$types_base/cluster-resource-type-minio.yaml"
  "$types_base/cluster-resource-type-rabbitmq.yaml"
  "$types_base/cluster-resource-type-milvus.yaml"
  "$types_base/cluster-resource-type-redis.yaml"
  "$project_base/resources.yaml"
  "$project_base/resource-bindings.yaml"
)

for file in "${required[@]}"; do
  test -f "$file" || {
    printf 'missing Agent Platform managed resource file: %s\n' "$file" >&2
    exit 1
  }
done

grep -Fq 'retainPolicy: Retain' "$types_base/cluster-resource-type-postgresql.yaml"
grep -Fq 'name: minio' "$types_base/cluster-resource-type-minio.yaml"
grep -Fq 'quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z' "$types_base/cluster-resource-type-minio.yaml"
grep -Fq 'quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z' "$types_base/cluster-resource-type-minio.yaml"
grep -Fq 'secretPath: agent-platform/development/minio' "$project_base/resources.yaml"
grep -Fq 'rabbitmq:4.2.6-management' "$types_base/cluster-resource-type-rabbitmq.yaml"
if grep -Fq 'applied.rabbitmq.status' "$types_base/cluster-resource-type-rabbitmq.yaml"; then
  printf 'RabbitMQ contract must not depend on custom resource status propagation\n' >&2
  exit 1
fi
grep -Fq 'value: "${metadata.resourceName}.${metadata.namespace}.svc.cluster.local"' "$types_base/cluster-resource-type-rabbitmq.yaml"
grep -Fq 'value: "${metadata.resourceName}-default-user"' "$types_base/cluster-resource-type-rabbitmq.yaml"
grep -Fq 'id: readiness' "$types_base/cluster-resource-type-rabbitmq.yaml"
grep -Fq 'bash -c "</dev/tcp/${metadata.resourceName}/5672"' "$types_base/cluster-resource-type-rabbitmq.yaml"
grep -Fq 'milvusdb/milvus:v2.6.16' "$types_base/cluster-resource-type-milvus.yaml"
grep -Fq 'endpoint: "${parameters.storageEndpoint}.${metadata.namespace}.svc.cluster.local:9000"' "$types_base/cluster-resource-type-milvus.yaml"
grep -Fq 'name: MINIO_PORT' "$types_base/cluster-resource-type-milvus.yaml"
grep -Fq 'value: "9000"' "$types_base/cluster-resource-type-milvus.yaml"
grep -Fq 'storageEndpoint: minio' "$project_base/resources.yaml"
if grep -Fq 'storageEndpoint: minio:9000' "$project_base/resources.yaml"; then
  printf 'Milvus storage endpoint must be expanded to a cross-namespace FQDN\n' >&2
  exit 1
fi
grep -Fq 'redis:8.2.7-alpine' "$types_base/cluster-resource-type-redis.yaml"
grep -Fq 'kind: ExternalSecret' "$types_base/cluster-resource-type-redis.yaml"
grep -Fq 'appendonly yes' "$types_base/cluster-resource-type-redis.yaml"
grep -Fq 'name: REDISCLI_AUTH' "$types_base/cluster-resource-type-redis.yaml"
grep -Fq 'redis-cli ping' "$types_base/cluster-resource-type-redis.yaml"
grep -Fq 'secretPath: agent-platform/development/redis' "$project_base/resources.yaml"
grep -Fq 'enableSuperuserAccess: true' platform/apis/postgresql/composition.yaml
grep -Fq 'user langfuse on >{{ .langfuse_password }}' "$types_base/cluster-resource-type-redis.yaml"
grep -Fq 'property: langfuse_password' "$types_base/cluster-resource-type-redis.yaml"
grep -Fq 'langfuseDatabase: 1' "$project_base/resources.yaml"
grep -Fq 'key: langfuse_password' "$types_base/cluster-resource-type-redis.yaml"
grep -Fq 'databaseName: agent_platform' "$project_base/resources.yaml"
test "$(grep -c '^kind: Resource$' "$project_base/resources.yaml")" -ge 6
grep -Fq 'name: postgresql-development' "$project_base/resource-bindings.yaml"
grep -Fq 'resourceRelease: postgresql-' "$project_base/resource-bindings.yaml"
grep -Fq 'name: redis-development' "$project_base/resource-bindings.yaml"
grep -Fq 'resourceRelease: redis-' "$project_base/resource-bindings.yaml"
binding_count="$(grep -c '^kind: ResourceReleaseBinding$' "$project_base/resource-bindings.yaml")"
if [[ "$binding_count" != 5 && "$binding_count" != 8 ]]; then
  printf 'expected either 5 bootstrap bindings or 8 fully pinned bindings, got %s\n' "$binding_count" >&2
  exit 1
fi
test "$(grep -c 'retainPolicy: Retain' "$project_base/resource-bindings.yaml")" -eq "$binding_count"
if [[ "$binding_count" == 8 ]]; then
  grep -Fq 'resourceRelease: redis-78bc6c7cb' "$project_base/resource-bindings.yaml"
  grep -Fq 'resourceRelease: clickhouse-78f9964f7f' "$project_base/resource-bindings.yaml"
  grep -Fq 'resourceRelease: langfuse-96675c84c' "$project_base/resource-bindings.yaml"
  grep -Fq 'resourceRelease: langfuse-retention-5999ddbc97' "$project_base/resource-bindings.yaml"
fi

rendered="$(mktemp "${TMPDIR:-/tmp}/agent-platform-resources.XXXXXX")"
trap 'rm -f "$rendered"' EXIT

kustomize build "$types_base" >"$rendered"
kubectl apply --server-side --dry-run=server --force-conflicts \
  --field-manager=agent-platform-contract -f "$rendered" >/dev/null
kustomize build "$project_base" >"$rendered"
kubectl apply --server-side --dry-run=server --force-conflicts \
  --field-manager=agent-platform-contract -f "$rendered" >/dev/null

printf 'Agent Platform managed resources contract: PASS\n'
