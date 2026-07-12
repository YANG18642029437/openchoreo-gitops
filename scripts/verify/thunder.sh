#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
values="$repo_root/platform/thunder/values.yaml"
application="$repo_root/clusters/homelab/applications/13-thunder.yaml"

test -f "$values"
test -f "$application"

grep -q 'thunder.openchoreo.home.arpa' "$values"
grep -q 'thunder-bootstrap-secrets' "$values"
grep -q 'storageClass: nfs-shared' "$values"
grep -q 'enableFsGroup: false' "$values"

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
