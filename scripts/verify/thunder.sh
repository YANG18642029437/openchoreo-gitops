#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
values="$repo_root/platform/thunder/values.yaml"
application="$repo_root/clusters/homelab/applications/13-thunder.yaml"
control_plane_values="$repo_root/platform/openchoreo/control-plane-values.yaml"

test -f "$values"
test -f "$application"
test -f "$control_plane_values"

grep -q 'thunder.openchoreo.home.arpa' "$values"
grep -q 'thunder-bootstrap-secrets' "$values"
grep -q 'storageClass: nfs-thunder' "$values"
grep -q 'enableFsGroup: false' "$values"
grep -q 'pullPolicy: IfNotPresent' "$values"
grep -A1 '^setup:' "$values" | grep -q 'enabled: false'
grep -q 'path: platform/thunder-runtime' clusters/homelab/applications/13-thunder.yaml
grep -q 'storageClassName: nfs-thunder' platform/thunder-runtime/pvc.yaml

backstage_base_url="$(awk '/^backstage:/{in_backstage=1; next} in_backstage && /^  baseUrl:/{gsub(/[\"[:space:]]/, "", $2); print $2; exit}' "$control_plane_values")"
backstage_callback="${backstage_base_url}/api/auth/openchoreo-auth/handler/frame"
if ! grep -Fq "\"${backstage_callback}\"" "$values"; then
  printf 'Thunder Backstage redirect URI does not match Backstage baseUrl: %s\n' "$backstage_callback" >&2
  exit 1
fi

grep -q 'BACKSTAGE_UPDATE_PAYLOAD=' "$values"
grep -q -- '--data "$BACKSTAGE_UPDATE_PAYLOAD"' "$values"

grep -q 'mountPermissions: "0777"' infrastructure/storage/thunder-storage-class.yaml

for key in \
  THUNDER_ADMIN_PASSWORD \
  BACKSTAGE_CLIENT_SECRET \
  SYSTEM_APP_CLIENT_SECRET \
  WORKLOAD_PUBLISHER_CLIENT_SECRET; do
  grep -q "$key" "$values"
done

if grep -E 'Admin@123|Dev@123|PE@123|SRE@123|backstage-portal-secret|openchoreo-system-app-secret' "$values"; then
  printf 'fixed Thunder development credential found in GitOps values\n' >&2
  exit 1
fi

helm template thunder oci://ghcr.io/asgardeo/helm-charts/thunder \
  --version 0.28.0 \
  --namespace thunder \
  --values "$values" >/dev/null

printf 'Thunder GitOps contract: PASS\n'
