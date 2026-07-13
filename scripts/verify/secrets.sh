#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

managed_roots=(bootstrap clusters infrastructure platform)
existing_roots=()
for root in "${managed_roots[@]}"; do
  test -d "$root" && existing_roots+=("$root")
done

yaml_files=()
while IFS= read -r path; do
  yaml_files+=("$path")
done < <(find "${existing_roots[@]}" -type f \( -name '*.yaml' -o -name '*.yml' \) -print | sort)

ruby -ryaml -e '
  ARGV.each do |path|
    YAML.load_stream(File.read(path)).compact.each do |doc|
      next unless doc.is_a?(Hash) && doc["kind"] == "Secret"
      %w[data stringData].each do |field|
        payload = doc[field]
        next if payload.nil? || (payload.respond_to?(:empty?) && payload.empty?)
        warn "secret violation: inline #{field} in #{path}"
        exit 1
      end
    end
  end
' "${yaml_files[@]}"

if rg -n --pcre2 -- '-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----|(?i)^[[:space:]]*(password|token|api[_-]?key|secret):[[:space:]]*["\x27]?[A-Za-z0-9+/_.@-]{8,}' "${yaml_files[@]}"; then
  printf 'secret violation: credential or private key material\n' >&2
  exit 1
fi

printf 'gitops secrets: PASS\n'
