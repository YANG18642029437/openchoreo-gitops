#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

required=(
  clusters/homelab/applications/25-openchoreo-capabilities.yaml
  clusters/homelab/applications/26-smoke-app.yaml
  platform/openchoreo/capabilities/service.yaml
  examples/smoke-app/kustomization.yaml
  examples/smoke-app/component.yaml
  examples/smoke-app/workload.yaml
  examples/smoke-app/api.yaml
  examples/smoke-app/build.yaml
  examples/smoke-app/resource.yaml
  examples/smoke-app/resource-bindings.yaml
)

for path in "${required[@]}"; do
  test -f "$path" || { printf 'missing Phase 05 smoke file: %s\n' "$path" >&2; exit 1; }
done

grep -q 'name: service' platform/openchoreo/capabilities/service.yaml
grep -q 'dependencies.toContainerEnvs' platform/openchoreo/capabilities/service.yaml
grep -q 'kind: Component' examples/smoke-app/component.yaml
grep -q 'autoDeploy: true' examples/smoke-app/component.yaml
grep -q 'kind: Workload' examples/smoke-app/workload.yaml
grep -Eq 'image: harbor\.openchoreo\.home\.arpa/openchoreo/phase05-smoke@sha256:[a-f0-9]{64}' examples/smoke-app/workload.yaml
grep -q 'url: DATABASE_URL' examples/smoke-app/workload.yaml
grep -q 'visibility: \[external\]' examples/smoke-app/workload.yaml
grep -q 'kind: Resource' examples/smoke-app/resource.yaml
test "$(grep -c 'kind: ResourceReleaseBinding' examples/smoke-app/resource-bindings.yaml)" = 3
for environment in development staging production; do
  grep -q "environment: $environment" examples/smoke-app/resource-bindings.yaml
done

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
kustomize build platform/openchoreo/capabilities >"$rendered"
kubectl apply --dry-run=server -f "$rendered" >/dev/null
kustomize build examples/smoke-app >"$rendered"
kubectl apply --dry-run=server -f "$rendered" >/dev/null

printf 'OpenChoreo Phase 05 smoke contract: PASS\n'
