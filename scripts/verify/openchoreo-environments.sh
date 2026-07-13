#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

resources=platform/openchoreo/resources
required=(
  clusters/homelab/applications/23-platform-apis.yaml
  clusters/homelab/applications/24-environments.yaml
  "$resources/kustomization.yaml"
  "$resources/cluster-resource-type-postgresql.yaml"
  "$resources/environment-development.yaml"
  "$resources/environment-staging.yaml"
  "$resources/environment-production.yaml"
  "$resources/deployment-pipeline.yaml"
  "$resources/project.yaml"
  "$resources/README.md"
)

for path in "${required[@]}"; do
  test -f "$path" || {
    printf 'missing OpenChoreo environment file: %s\n' "$path" >&2
    exit 1
  }
done

grep -q 'path: platform/apis/postgresql' clusters/homelab/applications/23-platform-apis.yaml
grep -q 'argocd.argoproj.io/sync-wave: "60"' clusters/homelab/applications/23-platform-apis.yaml
grep -q 'path: platform/openchoreo/resources' clusters/homelab/applications/24-environments.yaml
grep -q 'argocd.argoproj.io/sync-wave: "70"' clusters/homelab/applications/24-environments.yaml
grep -q 'applications/23-platform-apis.yaml' clusters/homelab/kustomization.yaml
grep -q 'applications/24-environments.yaml' clusters/homelab/kustomization.yaml

crt="$resources/cluster-resource-type-postgresql.yaml"
grep -q 'kind: ClusterResourceType' "$crt"
grep -q 'apiVersion: database.openchoreo.io/v1alpha1' "$crt"
grep -q 'kind: XPostgreSQL' "$crt"
for field in environment storageGiB instances databaseName status.host status.port status.secretName; do
  grep -q "$field" "$crt"
done
for output in database username password url; do
  grep -A4 "name: $output" "$crt" | grep -q 'secretKeyRef:' || {
    printf 'PostgreSQL output %s must remain a data-plane Secret reference\n' "$output" >&2
    exit 1
  }
done
if rg -n --pcre2 '^[[:space:]]*(value|stringData):[[:space:]]*["\x27]?[A-Za-z0-9@._/+:-]{8,}["\x27]?[[:space:]]*$' "$crt"; then
  printf 'PostgreSQL ClusterResourceType contains a literal credential-like value\n' >&2
  exit 1
fi

grep -q 'name: development' "$resources/environment-development.yaml"
grep -q 'isProduction: false' "$resources/environment-development.yaml"
grep -q 'name: staging' "$resources/environment-staging.yaml"
grep -q 'isProduction: false' "$resources/environment-staging.yaml"
grep -q 'name: production' "$resources/environment-production.yaml"
grep -q 'isProduction: true' "$resources/environment-production.yaml"

pipeline="$resources/deployment-pipeline.yaml"
grep -q 'kind: DeploymentPipeline' "$pipeline"
test "$(grep -c 'kind: Environment' "$pipeline")" = 4
grep -A4 'name: development' "$pipeline" | grep -q 'name: staging'
grep -A4 'name: staging' "$pipeline" | grep -q 'name: production'
grep -q 'deploymentPipelineRef:' "$resources/project.yaml"
grep -A1 'deploymentPipelineRef:' "$resources/project.yaml" | grep -q 'name: default'

if rg -n 'kind: ReleasePipeline|manualApproval|autoPromotion' "$resources"; then
  printf 'OpenChoreo 1.1.2 API compatibility violation\n' >&2
  exit 1
fi

for contract in CompositeResourceDefinition Composition Function ClusterResourceType; do
  grep -q "kind: $contract" clusters/homelab/project.yaml
done

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
kustomize build "$resources" >"$rendered"
kubectl apply --dry-run=server -f "$rendered" >/dev/null
kustomize build clusters/homelab >/dev/null

printf 'OpenChoreo self-service environments contract: PASS\n'
