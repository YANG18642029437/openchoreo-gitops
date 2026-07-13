#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${KUBECONFIG:?KUBECONFIG must point to the protected homelab kubeconfig}"
command -v kubectl >/dev/null
command -v jq >/dev/null
command -v curl >/dev/null

expected_digest="$(sed -nE 's|^[[:space:]]*image: .*@(sha256:[a-f0-9]{64})|\1|p' "$repo_root/examples/smoke-app/workload.yaml")"
[[ "$expected_digest" =~ ^sha256:[a-f0-9]{64}$ ]]

for environment in development staging production; do
  kubectl wait -n default --for=condition=Ready \
    "releasebinding/phase05-smoke-$environment" --timeout=30s >/dev/null
  base="http://${environment}-default.apps.openchoreo.home.arpa/phase05-smoke-http"
  curl --noproxy '*' -fsS --max-time 10 "$base/healthz" | jq -e '.status == "ok"' >/dev/null
  curl --noproxy '*' -fsS --max-time 10 "$base/readyz" | jq -e '.status == "ready"' >/dev/null
  curl --noproxy '*' -fsS --max-time 10 "$base/api/db" | jq -e '.status == "ok"' >/dev/null
done

release_count="$(kubectl get releasebinding -n default -o json | jq -r \
  '[.items[] | select(.metadata.name | startswith("phase05-smoke-")) | .spec.releaseName] | unique | length')"
test "$release_count" = 1
approval="$(kubectl get releasebinding phase05-smoke-production -n default \
  -o jsonpath='{.metadata.annotations.phase05\.openchoreo\.io/approval}')"
test "$approval" = explicitly-approved-after-staging-validation

image_count="$(kubectl get deployment -A -l openchoreo.dev/component=phase05-smoke -o json | jq -r \
  '[.items[].spec.template.spec.containers[0].image] | unique | length')"
test "$image_count" = 1
kubectl get deployment -A -l openchoreo.dev/component=phase05-smoke -o json | jq -e \
  --arg digest "$expected_digest" 'all(.items[].spec.template.spec.containers[0].image; endswith($digest))' >/dev/null

kubectl get cluster.postgresql.cnpg.io -A -o json | jq -e '
  [.items[] | select(.metadata.name | startswith("r-phase05-postgresql-")) |
    (.spec.instances == .status.readyInstances)] | length == 3 and all' >/dev/null

metrics="$(kubectl -n openchoreo-observability-plane exec \
  prometheus-openchoreo-observability-0 -c prometheus -- wget -qO- \
  'http://127.0.0.1:9090/api/v1/query?query=smoke_http_requests_total')"
jq -e '.status == "success" and (.data.result | length) == 3' <<<"$metrics" >/dev/null

os_user="$(kubectl -n openchoreo-observability-plane get secret opensearch-admin-credentials \
  -o jsonpath='{.data.username}' | base64 -d)"
os_password="$(kubectl -n openchoreo-observability-plane get secret opensearch-admin-credentials \
  -o jsonpath='{.data.password}' | base64 -d)"
logs="$(kubectl -n openchoreo-observability-plane exec opensearch-master-0 -- \
  curl -sku "$os_user:$os_password" -H 'Content-Type: application/json' \
  'https://127.0.0.1:9200/container-logs-*/_search' \
  -d '{"size":0,"query":{"match_phrase":{"log":"\"path\":\"/api/db\""}}}')"
traces="$(kubectl -n openchoreo-observability-plane exec opensearch-master-0 -- \
  curl -sku "$os_user:$os_password" -H 'Content-Type: application/json' \
  'https://127.0.0.1:9200/otel-traces-*/_search' \
  -d '{"size":100,"query":{"match_all":{}}}')"
jq -e '.hits.total.value > 0' <<<"$logs" >/dev/null
jq -e 'any(.hits.hits[]; ._source.name == "GET /api/db")' <<<"$traces" >/dev/null
unset os_user os_password logs traces metrics

printf 'Phase 05 end-to-end platform validation: PASS\n'
