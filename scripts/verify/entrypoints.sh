#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
rendered="$(kubectl kustomize "$repo_root/clusters/homelab")"

grep -q 'name: argocd-access' <<<"$rendered"
grep -q 'path: infrastructure/argocd-access' <<<"$rendered"

access_rendered="$(kubectl kustomize "$repo_root/infrastructure/argocd-access")"
grep -q 'kind: Ingress' <<<"$access_rendered"
grep -q 'host: argocd.openchoreo.home.arpa' <<<"$access_rendered"
grep -q 'secretName: argocd-tls' <<<"$access_rendered"
grep -q 'name: argocd-server' <<<"$access_rendered"

printf 'platform entrypoints: PASS\n'
