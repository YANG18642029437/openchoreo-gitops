#!/usr/bin/env bash
set -euo pipefail

control_namespace="${OPENCHOREO_CONTROL_NAMESPACE:-openchoreo-control-plane}"
workflow_namespace="${OPENCHOREO_WORKFLOW_NAMESPACE:-openchoreo-workflow-plane}"
mode="${1:-all}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
chmod 0700 "$tmp_dir"

kubectl create namespace "$workflow_namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "$control_namespace" get secret cluster-gateway-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 --decode >"$tmp_dir/ca.crt"

kubectl -n "$workflow_namespace" create configmap cluster-gateway-ca \
  --from-file=ca.crt="$tmp_dir/ca.crt" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "Workflow Plane server CA prepared in namespace $workflow_namespace"

if [[ "$mode" == "prepare" ]]; then
  exit 0
fi

kubectl -n "$workflow_namespace" rollout status deployment/cluster-agent-workflowplane --timeout=20m

kubectl -n "$workflow_namespace" get secret cluster-agent-tls \
  -o jsonpath='{.data.ca\.crt}' | base64 --decode >"$tmp_dir/agent-ca.crt"

{
  cat <<'YAML'
apiVersion: openchoreo.dev/v1alpha1
kind: ClusterWorkflowPlane
metadata:
  name: default
spec:
  planeID: default
  clusterAgent:
    clientCA:
      value: |
YAML
  sed 's/^/        /' "$tmp_dir/agent-ca.crt"
  cat <<'YAML'
  secretStoreRef:
    name: openbao
YAML
} | kubectl apply -f - >/dev/null

echo 'ClusterWorkflowPlane/default registered'
