#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

api_dir=platform/apis/postgresql
definition="$api_dir/definition.yaml"
composition="$api_dir/composition.yaml"
functions="$api_dir/functions.yaml"
rbac="$api_dir/rbac.yaml"
development="$api_dir/examples/development.yaml"
production="$api_dir/examples/production.yaml"

required=(
  "$api_dir/kustomization.yaml"
  "$definition"
  "$composition"
  "$functions"
  "$rbac"
  "$development"
  "$production"
)

for path in "${required[@]}"; do
  test -f "$path" || {
    printf 'missing PostgreSQL API file: %s\n' "$path" >&2
    exit 1
  }
done

grep -q 'apiVersion: apiextensions.crossplane.io/v2' "$definition"
grep -q 'name: xpostgresqls.database.openchoreo.io' "$definition"
grep -q 'group: database.openchoreo.io' "$definition"
grep -q 'kind: XPostgreSQL' "$definition"
grep -q 'scope: Namespaced' "$definition"
for field in environment storageGiB instances databaseName ready host port secretName; do
  grep -q "$field:" "$definition"
done
for environment in development staging production; do
  grep -q -- "- $environment" "$definition"
done
grep -q 'minimum: 10' "$definition"
grep -q 'maximum: 100' "$definition"
grep -q 'minimum: 1' "$definition"
grep -q 'maximum: 3' "$definition"

grep -q 'mode: Pipeline' "$composition"
grep -q 'name: function-patch-and-transform' "$composition"
grep -q 'apiVersion: pt.fn.crossplane.io/v1beta1' "$composition"
grep -q 'apiVersion: postgresql.cnpg.io/v1' "$composition"
grep -q 'kind: Cluster' "$composition"
grep -q 'storageClass: local-path' "$composition"
grep -q 'development: "1"' "$composition"
grep -q 'staging: "2"' "$composition"
grep -q 'production: "3"' "$composition"
grep -q 'development: 10Gi' "$composition"
grep -q 'staging: 20Gi' "$composition"
grep -q 'production: 50Gi' "$composition"
grep -q 'bootstrap.initdb.database' "$composition" || grep -q 'toFieldPath: spec.bootstrap.initdb.database' "$composition"
grep -q 'toFieldPath: status.ready' "$composition"
grep -q 'fromFieldPath: status.readyInstances' "$composition"
for ready_count in 1 2 3; do
  grep -q "\"$ready_count\": \"true\"" "$composition"
done
grep -q 'toFieldPath: status.host' "$composition"
grep -q 'toFieldPath: status.port' "$composition"
grep -q 'toFieldPath: status.secretName' "$composition"
grep -Fq 'metadata.annotations["database.openchoreo.io/port"]' "$composition"

grep -q 'xpkg.crossplane.io/crossplane-contrib/function-patch-and-transform:v0.8.2' "$functions"
grep -q 'postgresql.cnpg.io' "$rbac"
grep -q 'clusters' "$rbac"
grep -q 'name: crossplane' "$rbac"

grep -q 'environment: development' "$development"
grep -q 'instances: 1' "$development"
grep -q 'storageGiB: 10' "$development"
grep -q 'environment: production' "$production"
grep -q 'instances: 3' "$production"
grep -q 'storageGiB: 50' "$production"

if rg -ni 'password:|proxmox|terraform' "$api_dir"; then
  printf 'PostgreSQL API contains a secret or infrastructure scope violation\n' >&2
  exit 1
fi

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
kustomize build "$api_dir" >"$rendered"
kubectl apply --dry-run=server -f "$rendered" >/dev/null

printf 'Crossplane PostgreSQL API contract: PASS\n'
