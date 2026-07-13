#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

logs_application=clusters/homelab/applications/17-observability-logs.yaml
traces_application=clusters/homelab/applications/18-observability-traces.yaml
metrics_application=clusters/homelab/applications/19-observability-metrics.yaml
plane_application=clusters/homelab/applications/20-openchoreo-observability-plane.yaml
logs_values=platform/observability/values-logs.yaml
traces_values=platform/observability/values-traces.yaml
metrics_values=platform/observability/values-metrics.yaml
plane_values=platform/openchoreo/observability-plane-values.yaml
secrets=platform/openchoreo/observability-runtime/external-secrets.yaml
bootstrap=scripts/operations/register-observability-plane.sh
external_secrets_application=clusters/homelab/applications/07-external-secrets.yaml
nfs_storage_class=infrastructure/storage/nfs-storage-class.yaml
chart_cache="${OPENCHOREO_CHART_CACHE:-}"

chart_ref() {
  local chart="$1" version="$2"
  if [[ -n "$chart_cache" && -s "$chart_cache/$chart-$version.tgz" ]]; then
    printf '%s\n' "$chart_cache/$chart-$version.tgz"
  else
    printf 'oci://ghcr.io/openchoreo/helm-charts/%s\n' "$chart"
  fi
}

for file in "$logs_application" "$traces_application" "$metrics_application" \
  "$plane_application" "$logs_values" "$traces_values" "$metrics_values" \
  "$plane_values" "$secrets"; do
  test -f "$file" || { echo "missing Observability Plane contract file: $file" >&2; exit 1; }
done
test -x "$bootstrap" || { echo "missing executable Observability Plane registration script" >&2; exit 1; }

grep -q 'targetRevision: 0.4.1' "$logs_application"
grep -q 'targetRevision: 0.4.1' "$traces_application"
grep -q 'targetRevision: 0.6.1' "$metrics_application"
grep -q 'argocd.argoproj.io/compare-options: ServerSideDiff=true' "$logs_application"
grep -q 'argocd.argoproj.io/compare-options: ServerSideDiff=true' "$traces_application"
grep -q 'argocd.argoproj.io/compare-options: ServerSideDiff=true' "$metrics_application"
grep -q 'targetRevision: 1.1.2' "$plane_application"
grep -q 'sync-wave: "40"' "$plane_application"
grep -q 'argocd.argoproj.io/compare-options: ServerSideDiff=true' "$plane_application"
grep -q 'argocd.argoproj.io/compare-options: ServerSideDiff=true' "$external_secrets_application"

for application in 17-observability-logs.yaml 18-observability-traces.yaml \
  19-observability-metrics.yaml 20-openchoreo-observability-plane.yaml; do
  grep -q "$application" clusters/homelab/kustomization.yaml
done

grep -q 'storageClass: local-path' "$logs_values"
grep -q 'size: 20Gi' "$logs_values"
grep -q 'containerLogs: "7d"' "$logs_values"
grep -A8 '^fluent-bit:' "$logs_values" | grep -q 'memory: 256Mi'
if grep -q 'OPENSEARCH_JAVA_OPTS' "$logs_values"; then
  echo 'OpenSearch Java options must use the chart opensearchJavaOpts value, not duplicate env entries' >&2
  exit 1
fi
grep -q 'openSearch:' "$traces_values"
grep -A1 'openSearch:' "$traces_values" | grep -q 'enabled: false'
grep -q 'traces: "7d"' "$traces_values"
grep -q 'storageClassName: local-path' "$metrics_values"
grep -q 'storage: 15Gi' "$metrics_values"

grep -q 'metallb.io/loadBalancerIPs: 192.168.2.155' "$plane_values"
grep -q 'secretName: observer-secret' "$plane_values"
grep -q 'openSearchSecretName: opensearch-admin-credentials' "$plane_values"
grep -q 'serverUrl: wss://cluster-gateway.openchoreo-control-plane.svc.cluster.local:8443/ws' "$plane_values"
grep -q 'kind: ExternalSecret' "$secrets"
grep -q 'name: openbao' "$secrets"
grep -q 'deletionPolicy: Retain' "$secrets"
grep -q 'conversionStrategy: Default' "$secrets"
grep -q 'storageclass.kubernetes.io/is-default-class: "false"' "$nfs_storage_class"
grep -q 'kind: ClusterObservabilityPlane' "$bootstrap"
grep -q 'observerURL:' "$bootstrap"

helm template observability-logs-opensearch \
  "$(chart_ref observability-logs-opensearch 0.4.1)" \
  --version 0.4.1 --namespace openchoreo-observability-plane \
  --values "$logs_values" >/dev/null
helm template observability-tracing-opensearch \
  "$(chart_ref observability-tracing-opensearch 0.4.1)" \
  --version 0.4.1 --namespace openchoreo-observability-plane \
  --values "$traces_values" >/dev/null
helm template observability-metrics-prometheus \
  "$(chart_ref observability-metrics-prometheus 0.6.1)" \
  --version 0.6.1 --namespace openchoreo-observability-plane \
  --values "$metrics_values" >/dev/null
helm template openchoreo-observability-plane \
  "$(chart_ref openchoreo-observability-plane 1.1.2)" \
  --version 1.1.2 --namespace openchoreo-observability-plane \
  --values "$plane_values" >/dev/null

echo 'OpenChoreo Observability Plane contract: PASS'
