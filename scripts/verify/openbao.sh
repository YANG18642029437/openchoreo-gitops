#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

application=clusters/homelab/applications/06-openbao.yaml

test -f "$application" || {
  echo 'missing OpenBao Application' >&2
  exit 1
}

ruby -ryaml -e '
  application = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
  ignored = application.dig("spec", "ignoreDifferences") || []
  matched = ignored.any? do |rule|
    rule["group"] == "admissionregistration.k8s.io" &&
      rule["kind"] == "MutatingWebhookConfiguration" &&
      rule["name"] == "openbao-agent-injector-cfg" &&
      (rule["jqPathExpressions"] || []).include?(".webhooks[]?.clientConfig.caBundle")
  end
  exit(matched ? 0 : 1)
' "$application" || {
  echo 'OpenBao injector caBundle drift is not ignored precisely' >&2
  exit 1
}

grep -q 'RespectIgnoreDifferences=true' "$application" || {
  echo 'OpenBao Application does not respect ignored runtime fields during sync' >&2
  exit 1
}

echo 'OpenBao GitOps drift contract: PASS'
