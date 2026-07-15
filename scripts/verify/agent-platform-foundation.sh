#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

bash scripts/verify/agent-platform-operators.sh
bash scripts/verify/agent-platform-rbac.sh
bash scripts/verify/agent-platform-control-plane.sh
bash scripts/verify/agent-platform-resources.sh
bash scripts/verify/render.sh

credential_pattern="-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|^[[:space:]]*(password|token|api[_-]?key|secret):[[:space:]]*[\"']?[A-Za-z0-9+/_.@-]{8,}"
if /usr/bin/grep -REni \
  --include='*.yaml' --include='*.yml' \
  -- \
  "$credential_pattern" \
  clusters infrastructure platform; then
  printf 'Agent Platform foundation contains credential-like material\n' >&2
  exit 1
fi

git diff --check
printf 'Agent Platform development foundation: PASS\n'
