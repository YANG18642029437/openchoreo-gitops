#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

rabbit_app=clusters/homelab/applications/22-rabbitmq-cluster-operator.yaml
milvus_app=clusters/homelab/applications/22-milvus-operator.yaml

for file in "$rabbit_app" "$milvus_app"; do
  test -f "$file" || {
    printf 'missing Agent Platform operator application: %s\n' "$file" >&2
    exit 1
  }
done

/usr/bin/grep -Fq 'repoURL: https://github.com/rabbitmq/cluster-operator.git' "$rabbit_app"
/usr/bin/grep -Fq 'targetRevision: v2.22.2' "$rabbit_app"
/usr/bin/grep -Fq 'path: config/installation' "$rabbit_app"
expected_rabbit_image='ghcr.io/rabbitmq/cluster-operator:2.22.2'
/usr/bin/grep -Fq "$expected_rabbit_image" "$rabbit_app" || {
  printf 'RabbitMQ Operator image must use published tag: %s\n' "$expected_rabbit_image" >&2
  exit 1
}
if /usr/bin/grep -Fq 'ghcr.io/rabbitmq/cluster-operator:v2.22.2' "$rabbit_app"; then
  printf 'RabbitMQ Operator image must not use the missing v2.22.2 tag\n' >&2
  exit 1
fi
/usr/bin/grep -Fq 'namespace: rabbitmq-system' "$rabbit_app"

/usr/bin/grep -Fq 'repoURL: https://zilliztech.github.io/milvus-operator/' "$milvus_app"
/usr/bin/grep -Fq 'chart: milvus-operator' "$milvus_app"
/usr/bin/grep -Fq 'targetRevision: 1.3.7' "$milvus_app"
/usr/bin/grep -Fq 'cert-manager:' "$milvus_app"
/usr/bin/grep -Fq 'enabled: false' "$milvus_app"
/usr/bin/grep -Fq 'namespace: milvus-operator' "$milvus_app"

for source in \
  'https://github.com/rabbitmq/cluster-operator.git' \
  'https://zilliztech.github.io/milvus-operator/'; do
  /usr/bin/grep -Fq -- "- $source" clusters/homelab/project.yaml
done

for app in \
  'applications/22-rabbitmq-cluster-operator.yaml' \
  'applications/22-milvus-operator.yaml'; do
  /usr/bin/grep -Fq -- "- $app" clusters/homelab/kustomization.yaml
done

kustomize build clusters/homelab >/dev/null
printf 'Agent Platform operators contract: PASS\n'
