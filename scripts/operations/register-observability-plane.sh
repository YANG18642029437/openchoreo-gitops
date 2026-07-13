#!/usr/bin/env bash
set -euo pipefail

control_namespace="${OPENCHOREO_CONTROL_NAMESPACE:-openchoreo-control-plane}"
observability_namespace="${OPENCHOREO_OBSERVABILITY_NAMESPACE:-openchoreo-observability-plane}"
mode="${1:-all}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
chmod 0700 "$tmp_dir"

kubectl create namespace "$observability_namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "$control_namespace" get secret cluster-gateway-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 --decode >"$tmp_dir/ca.crt"

kubectl -n "$observability_namespace" create configmap cluster-gateway-ca \
  --from-file=ca.crt="$tmp_dir/ca.crt" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "Observability Plane server CA prepared in namespace $observability_namespace"

if [[ "$mode" == "prepare" ]]; then
  exit 0
fi

kubectl -n "$observability_namespace" rollout status deployment/cluster-agent-observabilityplane --timeout=20m

kubectl -n "$observability_namespace" get secret cluster-agent-tls \
  -o jsonpath='{.data.ca\.crt}' | base64 --decode >"$tmp_dir/agent-ca.crt"

{
  cat <<'YAML'
apiVersion: openchoreo.dev/v1alpha1
kind: ClusterObservabilityPlane
metadata:
  name: default
spec:
  planeID: default
  observerURL: http://observer.openchoreo-observability-plane.svc.cluster.local:8080
  clusterAgent:
    clientCA:
      value: |
YAML
  sed 's/^/        /' "$tmp_dir/agent-ca.crt"
} | kubectl apply -f - >/dev/null

echo 'ClusterObservabilityPlane/default registered'
