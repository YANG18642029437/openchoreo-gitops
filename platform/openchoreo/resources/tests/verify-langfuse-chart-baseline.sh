#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$repo_root"

chart_version=1.5.39
values=platform/openchoreo/resources/tests/langfuse-chart-1.5.39-values.yaml
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

helm repo add langfuse-contract https://langfuse.github.io/langfuse-k8s --force-update >/dev/null
helm template langfuse langfuse-contract/langfuse \
  --version "$chart_version" \
  --namespace agent-platform-development \
  --values "$values" >"$rendered"

for dependency in postgresql valkey clickhouse minio zookeeper; do
  if grep -Eq "(^|[[:space:]/-])${dependency}([[:space:]/:-]|$)" "$rendered"; then
    printf 'official Langfuse chart unexpectedly rendered built-in dependency: %s\n' "$dependency" >&2
    exit 1
  fi
done

grep -Fq 'image: "langfuse/langfuse:3.212.0"' "$rendered"
grep -Fq 'image: "langfuse/langfuse-worker:3.212.0"' "$rendered"
grep -Fq 'path: /api/public/health' "$rendered"
grep -Fq 'path: /api/public/ready' "$rendered"
grep -Fq 'name: TELEMETRY_ENABLED' "$rendered"
grep -Fq 'name: AUTH_DISABLE_SIGNUP' "$rendered"

printf 'Langfuse Helm chart %s external dependency baseline: PASS\n' "$chart_version"
