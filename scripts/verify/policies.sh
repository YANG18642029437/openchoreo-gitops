#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

managed_roots=(bootstrap clusters infrastructure platform)
existing_roots=()
for root in "${managed_roots[@]}"; do
  test -d "$root" && existing_roots+=("$root")
done

if ((${#existing_roots[@]} == 0)); then
  printf 'no managed GitOps roots found\n' >&2
  exit 1
fi

yaml_files=()
while IFS= read -r path; do
  yaml_files+=("$path")
done < <(find "${existing_roots[@]}" -type f \( -name '*.yaml' -o -name '*.yml' \) -print | sort)

if ((${#yaml_files[@]} == 0)); then
  printf 'no managed YAML files found\n' >&2
  exit 1
fi

if rg -n '^[[:space:]]*targetRevision:[[:space:]]*(""|\x27\x27)?[[:space:]]*$' "${yaml_files[@]}"; then
  printf 'policy violation: empty targetRevision\n' >&2
  exit 1
fi

if rg -n '^[[:space:]]*(image|repository):[[:space:]]*[^#[:space:]]+:latest([[:space:]]|$)|^[[:space:]]*tag:[[:space:]]*["\x27]?latest["\x27]?([[:space:]]|$)' "${yaml_files[@]}"; then
  printf 'policy violation: latest image tag\n' >&2
  exit 1
fi

if rg -n '^[[:space:]]*chart:[[:space:]]*' "${yaml_files[@]}" >/dev/null; then
  chart_count="$(rg -c '^[[:space:]]*chart:[[:space:]]*' "${yaml_files[@]}" | awk -F: '{sum += $2} END {print sum + 0}')"
  revision_count="$(rg -c '^[[:space:]]*targetRevision:[[:space:]]*[^[:space:]#]+' "${yaml_files[@]}" | awk -F: '{sum += $2} END {print sum + 0}')"
  if ((revision_count < chart_count)); then
    printf 'policy violation: Helm chart without fixed targetRevision\n' >&2
    exit 1
  fi
fi

if rg -n '^[[:space:]]*kind:[[:space:]]*(Kustomization|HelmRelease)[[:space:]]*$' "${yaml_files[@]}" \
  | while IFS= read -r match; do
      file="${match%%:*}"
      rg -q '^[[:space:]]*apiVersion:[[:space:]]*(kustomize|helm)\.toolkit\.fluxcd\.io/' "$file" && printf '%s\n' "$match"
    done \
  | grep -q .; then
  printf 'policy violation: active Flux resource in managed roots\n' >&2
  exit 1
fi

printf 'gitops policies: PASS\n'
