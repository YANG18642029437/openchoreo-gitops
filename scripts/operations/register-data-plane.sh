#!/usr/bin/env bash
set -euo pipefail

control_namespace="${OPENCHOREO_CONTROL_NAMESPACE:-openchoreo-control-plane}"
data_namespace="${OPENCHOREO_DATA_NAMESPACE:-openchoreo-data-plane}"
mode="${1:-all}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
chmod 0700 "$tmp_dir"

kubectl create namespace "$data_namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "$control_namespace" get secret cluster-gateway-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 --decode >"$tmp_dir/ca.crt"

kubectl -n "$data_namespace" create configmap cluster-gateway-ca \
  --from-file=ca.crt="$tmp_dir/ca.crt" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "Data Plane server CA prepared in namespace $data_namespace"

if [[ "$mode" == "prepare" ]]; then
  exit 0
fi

kubectl -n "$data_namespace" rollout status deployment/cluster-agent-dataplane --timeout=20m

kubectl -n "$data_namespace" get secret cluster-agent-tls \
  -o jsonpath='{.data.ca\.crt}' | base64 --decode >"$tmp_dir/agent-ca.crt"

{
  cat <<'YAML'
apiVersion: openchoreo.dev/v1alpha1
kind: ClusterDataPlane
metadata:
  name: default
spec:
  planeID: default
  clusterAgent:
    clientCA:
      value: |
YAML
  sed 's/^/        /' "$tmp_dir/agent-ca.crt"
  cat <<YAML
  secretStoreRef:
    name: openbao
  gateway:
    ingress:
      external:
        http:
          host: apps.openchoreo.home.arpa
          listenerName: http
          port: 80
        name: gateway-default
        namespace: $data_namespace
YAML
} | kubectl apply -f - >/dev/null

echo 'ClusterDataPlane/default registered'
