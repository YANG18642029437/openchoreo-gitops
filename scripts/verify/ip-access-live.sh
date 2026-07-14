#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
infra_root="$(cd "$repo_root/../openchoreo-infra" && pwd)"
ca_file="${IP_ACCESS_CA_FILE:-$infra_root/.private/pki/root-ca.crt}"
ip="${IP_ACCESS_IP:-192.168.2.154}"

test -r "$ca_file" || {
  printf 'CA certificate is not readable: %s\n' "$ca_file" >&2
  exit 1
}

checks=(
  'Argo CD|31001|/'
  'Harbor|31002|/'
  'OpenBao|31003|/ui/'
  'OpenChoreo|31004|/'
  'Observer health API|31005|/health'
  'Thunder Console|31006|/console/'
)

for check in "${checks[@]}"; do
  IFS='|' read -r name port request_path <<<"$check"
  result="$(curl --noproxy '*' --silent --show-error --location \
    --cacert "$ca_file" --connect-timeout 5 --max-time 30 \
    --output /dev/null --write-out '%{http_code}|%{url_effective}' \
    "https://$ip:$port$request_path")"
  IFS='|' read -r code effective_url <<<"$result"
  case "$code" in
    2??|3??) ;;
    *) printf '%s failed: HTTP %s (%s)\n' "$name" "$code" "$effective_url" >&2; exit 1 ;;
  esac
  if [[ "$effective_url" == *openchoreo.home.arpa* ]]; then
    printf '%s redirected back to a canonical hostname: %s\n' "$name" "$effective_url" >&2
    exit 1
  fi
  printf '%-20s PASS HTTP %s %s\n' "$name" "$code" "$effective_url"
done

openssl s_client -connect "$ip:31001" -servername "$ip" \
  -CAfile "$ca_file" -verify_ip "$ip" </dev/null 2>&1 |
  grep -q 'Verify return code: 0 (ok)'

if command -v kubectl >/dev/null 2>&1; then
  test "$(kubectl -n argocd get service argocd-server -o jsonpath='{.spec.type}')" = ClusterIP
  test "$(kubectl -n ingress-nginx get service ingress-nginx-controller -o jsonpath='{.spec.type}')" = LoadBalancer
  test "$(kubectl -n openchoreo-observability-plane get service observer -o jsonpath='{.spec.type}')" = ClusterIP
  test "$(kubectl -n thunder get service thunder-service -o jsonpath='{.spec.type}')" = ClusterIP
  ranges="$(kubectl -n platform-access get service ip-access -o jsonpath='{.spec.loadBalancerSourceRanges[*]}')"
  test "$ranges" = '10.8.0.10/32'
fi

printf 'IP port Web access live verification: PASS\n'
