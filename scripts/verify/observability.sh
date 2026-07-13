#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workload="$repo_root/examples/smoke-app/workload.yaml"
app="$repo_root/examples/smoke-app/app/main.go"

grep -q 'OTEL_EXPORTER_OTLP_ENDPOINT' "$workload"
grep -q '/metrics' "$app"
grep -q '/v1/traces' "$app"
grep -q 'smoke_http_requests_total' "$app"

printf 'Phase 05 observability contract: PASS\n'
