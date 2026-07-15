# Agent Platform 托管资源实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 通过 OpenChoreo 在 `agent-platform/development` 中创建共享 MinIO、单副本 RabbitMQ 和 standalone Milvus，并把实际 ResourceRelease 固定回 Git。

**Architecture:** `openchoreo-gitops` 提供三个 ClusterResourceType、三个 Resource 和三个 ResourceReleaseBinding；RabbitMQ/Milvus CR 由各自 Operator 执行，MinIO 由 OpenChoreo 直接渲染 StatefulSet。`openchoreo-infra` 在本机 `.private` 生成凭据并同步到 OpenBao，数据平面通过 ExternalSecret 获取，Git 中不保存明文。

**Tech Stack:** OpenChoreo 1.1.2、Argo CD、Kustomize、OpenBao、External Secrets Operator、RabbitMQ Cluster Operator 2.22.2、Milvus Operator 1.3.7、MinIO、Bash 3.2、Ruby 2.6、kubectl。

---

## 文件结构

### `openchoreo-infra`

- Create: `scripts/prepare/agent-platform-secrets.sh`：本地生成或复用 MinIO 凭据文件。
- Create: `scripts/bootstrap/initialize-agent-platform-secrets.sh`：把本地凭据幂等同步到 OpenBao。
- Create: `scripts/verify/agent-platform-secrets.sh`：测试本地生成、权限、幂等和脚本安全合同。
- Modify: `scripts/verify/phase01.sh`：纳入新验证器和必需文件。
- Modify: `README.md`：记录凭据入口与命令。
- Modify: `logs/README.md`：登记脱敏操作记录。
- Create during remote execution: `logs/2026-07-15-agent-platform-secrets.md`：只记录状态、路径和验证结论。
- Create locally and ignored: `.private/openbao/agent-platform.env`：保存真实 `MINIO_ROOT_USER`、`MINIO_ROOT_PASSWORD`。

### `openchoreo-gitops`

- Create: `platform/openchoreo/resources/cluster-resource-type-minio.yaml`：共享 MinIO 资源合同。
- Create: `platform/openchoreo/resources/cluster-resource-type-rabbitmq.yaml`：RabbitMQ Operator 资源合同。
- Create: `platform/openchoreo/resources/cluster-resource-type-milvus.yaml`：Milvus Operator 资源合同。
- Modify: `platform/openchoreo/resources/kustomization.yaml`：注册三个类型。
- Modify: `platform/openchoreo/resources/README.md`：说明资源类型和运行边界。
- Create: `platform/openchoreo/agent-platform/resources.yaml`：创建三个 Resource。
- Create: `platform/openchoreo/agent-platform/resource-bindings.yaml`：创建三个 development Binding。
- Modify: `platform/openchoreo/agent-platform/kustomization.yaml`：注册 Resource 与 Binding。
- Modify: `platform/openchoreo/agent-platform/README.md`：记录发布顺序、固定 Release 和凭据边界。
- Create: `scripts/verify/agent-platform-resources.sh`：资源合同与 Server-Side Dry Run 测试。
- Modify: `scripts/verify/agent-platform-foundation.sh`：纳入新测试。
- Modify: `README.md`：更新文件索引和维护入口。

## Task 1：为本地凭据生命周期编写失败测试

**Files:**
- Create: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/scripts/verify/agent-platform-secrets.sh`
- Modify later: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/scripts/verify/phase01.sh`

- [ ] **Step 1：在 `openchoreo-infra` 创建普通分支并记录基线**

Run:

```bash
cd /Users/yangyongxiang/Desktop/code/github/openchoreo-infra
git status --short --branch
git switch -c codex/agent-platform-managed-resources
git rev-parse HEAD
```

Expected: 工作区干净，从 `66ded15` 或执行时最新的 `origin/main` 创建分支；不创建 worktree。

- [ ] **Step 2：添加只依赖临时目录的失败测试**

使用 `apply_patch` 创建 `scripts/verify/agent-platform-secrets.sh`，测试必须包含以下完整行为：

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
prepare="$repo_root/scripts/prepare/agent-platform-secrets.sh"
bootstrap="$repo_root/scripts/bootstrap/initialize-agent-platform-secrets.sh"

test -x "$prepare"
test -x "$bootstrap"
bash -n "$prepare"
bash -n "$bootstrap"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-platform-secrets.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
secret_file="$tmp_dir/agent-platform.env"

first_output="$(AGENT_PLATFORM_SECRETS_FILE="$secret_file" "$prepare")"
test -s "$secret_file"
grep -q '^MINIO_ROOT_USER=' "$secret_file"
grep -q '^MINIO_ROOT_PASSWORD=' "$secret_file"
case "$(uname -s)" in
  Darwin) file_mode="$(stat -f '%Lp' "$secret_file")" ;;
  Linux) file_mode="$(stat -c '%a' "$secret_file")" ;;
  *) exit 1 ;;
esac
test "$file_mode" = 600

set -a
source "$secret_file"
set +a
test "$MINIO_ROOT_USER" = agent-platform
test "${#MINIO_ROOT_PASSWORD}" -ge 32
if printf '%s\n' "$first_output" | grep -Fq "$MINIO_ROOT_PASSWORD"; then
  printf 'prepare script leaked generated password\n' >&2
  exit 1
fi

first_hash="$(shasum -a 256 "$secret_file" | awk '{print $1}')"
second_output="$(AGENT_PLATFORM_SECRETS_FILE="$secret_file" "$prepare")"
second_hash="$(shasum -a 256 "$secret_file" | awk '{print $1}')"
test "$first_hash" = "$second_hash"
if printf '%s\n' "$second_output" | grep -Fq "$MINIO_ROOT_PASSWORD"; then
  printf 'prepare rerun leaked existing password\n' >&2
  exit 1
fi

grep -Fq 'openchoreo/agent-platform/development/minio' "$bootstrap"
grep -Fq 'root_user' "$bootstrap"
grep -Fq 'root_password' "$bootstrap"
grep -Fq 'agent-platform.env' "$bootstrap"

printf 'Agent Platform local secret contract: PASS\n'
```

- [ ] **Step 3：运行测试并确认 RED**

Run:

```bash
cd /Users/yangyongxiang/Desktop/code/github/openchoreo-infra
bash scripts/verify/agent-platform-secrets.sh
```

Expected: FAIL，失败原因是 `scripts/prepare/agent-platform-secrets.sh` 或 `scripts/bootstrap/initialize-agent-platform-secrets.sh` 尚不存在，而不是测试语法错误。

## Task 2：实现本地生成与 OpenBao 同步

**Files:**
- Create: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/scripts/prepare/agent-platform-secrets.sh`
- Create: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/scripts/bootstrap/initialize-agent-platform-secrets.sh`
- Modify: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/scripts/verify/phase01.sh`
- Modify: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/README.md`

- [ ] **Step 1：实现本地凭据准备脚本**

脚本必须：使用 `AGENT_PLATFORM_SECRETS_FILE` 覆盖路径；文件不存在时生成 `agent-platform` 用户和不少于 32 字符的随机密码；存在时保持内容不变；目录 `0700`、文件 `0600`；不输出真实值。

关键实现：

```bash
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
secret_file="${AGENT_PLATFORM_SECRETS_FILE:-$repo_root/.private/openbao/agent-platform.env}"
secret_dir="$(dirname "$secret_file")"
install -d -m 0700 "$secret_dir"

if [ ! -s "$secret_file" ]; then
  umask 077
  password="$(openssl rand -base64 36 | tr -d '\n')"
  install -m 0600 /dev/null "$secret_file"
  {
    printf 'MINIO_ROOT_USER=agent-platform\n'
    printf 'MINIO_ROOT_PASSWORD=%s\n' "$password"
  } >"$secret_file"
  unset password
fi

chmod 0600 "$secret_file"
set -a
source "$secret_file"
set +a
test "$MINIO_ROOT_USER" = agent-platform
test "${#MINIO_ROOT_PASSWORD}" -ge 32
unset MINIO_ROOT_USER MINIO_ROOT_PASSWORD
printf 'Agent Platform local secret preparation: PASS\n'
```

- [ ] **Step 2：实现 OpenBao 初始化脚本**

脚本复用 `.private/kubeconfigs/homelab-admin.yaml`、`.private/openbao/init.json` 和本地 env 文件。写入路径固定为 `openchoreo/agent-platform/development/minio`。先读取当前版本并比较；相同则不产生新版本，不同才写入；所有 `bao` 输出重定向或交给 `jq -e`，不得打印字段值。

关键实现合同：

```bash
kubeconfig="${KUBECONFIG:-$repo_root/.private/kubeconfigs/homelab-admin.yaml}"
secret_file="${AGENT_PLATFORM_SECRETS_FILE:-$repo_root/.private/openbao/agent-platform.env}"
init_file="$repo_root/.private/openbao/init.json"
secret_path='openchoreo/agent-platform/development/minio'

test -s "$secret_file"
test -s "$init_file"
set -a
source "$secret_file"
set +a
root_token="$(jq -er '.root_token' "$init_file")"

bao() {
  kubectl --kubeconfig "$kubeconfig" -n openbao exec openbao-0 -- \
    env BAO_TOKEN="$root_token" bao "$@"
}

current_json="$(bao kv get -format=json "$secret_path" 2>/dev/null || true)"
current_user="$(printf '%s' "$current_json" | jq -r '.data.data.root_user // empty')"
current_password="$(printf '%s' "$current_json" | jq -r '.data.data.root_password // empty')"
if [ "$current_user" != "$MINIO_ROOT_USER" ] || [ "$current_password" != "$MINIO_ROOT_PASSWORD" ]; then
  bao kv put "$secret_path" \
    root_user="$MINIO_ROOT_USER" \
    root_password="$MINIO_ROOT_PASSWORD" >/dev/null
fi

bao kv get -format=json "$secret_path" | jq -e \
  '.data.data.root_user | type == "string" and length > 0' >/dev/null
bao kv get -format=json "$secret_path" | jq -e \
  '.data.data.root_password | type == "string" and length >= 32' >/dev/null
unset root_token current_json current_user current_password \
  MINIO_ROOT_USER MINIO_ROOT_PASSWORD
printf 'Agent Platform OpenBao secret initialization: PASS\n'
```

- [ ] **Step 3：纳入 Phase 01 与 README**

在 `scripts/verify/phase01.sh` 的三个基础验证器之后调用：

```bash
./scripts/verify/agent-platform-secrets.sh
```

把三个新脚本加入 `required=(...)`，README 的 `.private` 章节增加：

```bash
./scripts/prepare/agent-platform-secrets.sh
./scripts/bootstrap/initialize-agent-platform-secrets.sh
```

README 只能记录路径、用途和权限，不记录任何真实值。

- [ ] **Step 4：运行测试并确认 GREEN**

Run:

```bash
chmod +x scripts/prepare/agent-platform-secrets.sh \
  scripts/bootstrap/initialize-agent-platform-secrets.sh \
  scripts/verify/agent-platform-secrets.sh
bash scripts/verify/agent-platform-secrets.sh
REQUIRE_GITLEAKS=1 ./scripts/verify/phase01.sh
```

Expected: 两个入口均 PASS；测试只在临时目录写入模拟凭据；工作区指纹不被 Phase 01 改变。

- [ ] **Step 5：提交基础设施本地能力**

```bash
git add README.md scripts/prepare/agent-platform-secrets.sh \
  scripts/bootstrap/initialize-agent-platform-secrets.sh \
  scripts/verify/agent-platform-secrets.sh scripts/verify/phase01.sh
git commit -s -m "feat: manage Agent Platform OpenBao secrets"
```

## Task 3：为 OpenChoreo 资源合同编写失败测试

**Files:**
- Create: `scripts/verify/agent-platform-resources.sh`
- Modify later: `scripts/verify/agent-platform-foundation.sh`

- [ ] **Step 1：创建资源合同测试**

测试至少检查以下文件存在：

```bash
types_base=platform/openchoreo/resources
project_base=platform/openchoreo/agent-platform
required=(
  "$types_base/cluster-resource-type-minio.yaml"
  "$types_base/cluster-resource-type-rabbitmq.yaml"
  "$types_base/cluster-resource-type-milvus.yaml"
  "$project_base/resources.yaml"
  "$project_base/resource-bindings.yaml"
)
for file in "${required[@]}"; do
  test -f "$file" || {
    printf 'missing Agent Platform managed resource file: %s\n' "$file" >&2
    exit 1
  }
done
```

并使用固定字符串检查：

```bash
grep -Fq 'name: minio' "$types_base/cluster-resource-type-minio.yaml"
grep -Fq 'quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z' "$types_base/cluster-resource-type-minio.yaml"
grep -Fq 'quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z' "$types_base/cluster-resource-type-minio.yaml"
grep -Fq 'secretPath: agent-platform/development/minio' "$project_base/resources.yaml"
grep -Fq 'rabbitmq:4.2.6-management' "$types_base/cluster-resource-type-rabbitmq.yaml"
grep -Fq 'milvusdb/milvus:v2.6.16' "$types_base/cluster-resource-type-milvus.yaml"
test "$(grep -c '^kind: Resource$' "$project_base/resources.yaml")" -eq 3
test "$(grep -c '^kind: ResourceReleaseBinding$' "$project_base/resource-bindings.yaml")" -eq 3
test "$(grep -c 'retainPolicy: Retain' "$project_base/resource-bindings.yaml")" -eq 3
```

渲染与 Server-Side Dry Run：

```bash
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
kustomize build "$types_base" >"$rendered"
kubectl apply --server-side --dry-run=server -f "$rendered" >/dev/null
kustomize build "$project_base" >"$rendered"
kubectl apply --server-side --dry-run=server -f "$rendered" >/dev/null
```

- [ ] **Step 2：运行测试并确认 RED**

Run:

```bash
bash scripts/verify/agent-platform-resources.sh
```

Expected: FAIL，第一项缺失文件为 `cluster-resource-type-minio.yaml`。

## Task 4：实现 MinIO ClusterResourceType

**Files:**
- Create: `platform/openchoreo/resources/cluster-resource-type-minio.yaml`
- Modify: `platform/openchoreo/resources/kustomization.yaml`

- [ ] **Step 1：添加 MinIO 参数与输出合同**

定义：

```yaml
spec:
  parameters:
    openAPIV3Schema:
      type: object
      required: [secretPath]
      properties:
        secretPath:
          type: string
          minLength: 1
        storageClass:
          type: string
          default: nfs-shared
        storageGiB:
          type: integer
          default: 20
          minimum: 10
          maximum: 200
  retainPolicy: Retain
  outputs:
    - name: host
      value: "${metadata.resourceName}.${metadata.namespace}.svc.cluster.local"
    - name: port
      value: "9000"
    - name: secretName
      value: "${metadata.resourceName}-creds"
    - name: accessKey
      secretKeyRef:
        name: "${metadata.resourceName}-creds"
        key: accesskey
    - name: secretKey
      secretKeyRef:
        name: "${metadata.resourceName}-creds"
        key: secretkey
```

- [ ] **Step 2：添加 ExternalSecret、Service、StatefulSet 和 Bucket Job**

必须使用以下固定合同：

```yaml
resources:
  - id: credentials
    readyWhen: '${has(applied.credentials.status.conditions) && applied.credentials.status.conditions.exists(c, c.type == "Ready" && c.status == "True")}'
    template:
      apiVersion: external-secrets.io/v1
      kind: ExternalSecret
      metadata:
        name: ${metadata.resourceName}-creds
        namespace: ${metadata.namespace}
        labels: ${metadata.labels}
      spec:
        secretStoreRef:
          kind: ClusterSecretStore
          name: openbao
        target:
          name: ${metadata.resourceName}-creds
          creationPolicy: Owner
          template:
            type: Opaque
            data:
              MINIO_ROOT_USER: "{{ .root_user }}"
              MINIO_ROOT_PASSWORD: "{{ .root_password }}"
              accesskey: "{{ .root_user }}"
              secretkey: "{{ .root_password }}"
        data:
          - secretKey: root_user
            remoteRef:
              key: ${parameters.secretPath}
              property: root_user
          - secretKey: root_password
            remoteRef:
              key: ${parameters.secretPath}
              property: root_password
```

Service 固定为 `metadata.resourceName`，端口为 `9000/9001`；StatefulSet 单副本，镜像固定，探针使用 `/minio/health/ready` 与 `/minio/health/live`，`volumeClaimTemplates` 使用 `nfs-shared 20Gi`。Bucket Job 使用唯一名称 `${metadata.name}-buckets` 并执行：

```sh
until mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"; do sleep 2; done
mc mb --ignore-existing local/milvus
mc mb --ignore-existing local/knowledge-base
```

Job 的 `readyWhen` 为：

```yaml
readyWhen: '${has(applied.buckets.status.succeeded) && applied.buckets.status.succeeded > 0}'
```

- [ ] **Step 3：注册文件并运行局部验证**

在 `platform/openchoreo/resources/kustomization.yaml` 添加：

```yaml
  - cluster-resource-type-minio.yaml
```

Run:

```bash
kustomize build platform/openchoreo/resources >/dev/null
kubectl apply --server-side --dry-run=server \
  -f platform/openchoreo/resources/cluster-resource-type-minio.yaml >/dev/null
```

Expected: exit 0，未创建集群资源。

## Task 5：实现 RabbitMQ 与 Milvus ClusterResourceType

**Files:**
- Create: `platform/openchoreo/resources/cluster-resource-type-rabbitmq.yaml`
- Create: `platform/openchoreo/resources/cluster-resource-type-milvus.yaml`
- Modify: `platform/openchoreo/resources/kustomization.yaml`

- [ ] **Step 1：实现 RabbitMQ 类型**

参数：`replicas` 默认且限制为 `1`，`storageClass` 默认 `local-path`，`storageGiB` 默认 `10`。模板固定：

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: ${metadata.resourceName}
  namespace: ${metadata.namespace}
  labels: ${metadata.labels}
spec:
  replicas: ${parameters.replicas}
  image: rabbitmq:4.2.6-management
  persistence:
    storageClassName: ${parameters.storageClass}
    storage: "${string(parameters.storageGiB) + 'Gi'}"
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: "1"
      memory: 2Gi
```

就绪条件同时要求 `AllReplicasReady` 和 `ClusterAvailable` 为 `True`。输出从 `status.defaultUser` 解析 Service、Secret 和 username/password 的 Secret key 引用，端口固定为 `5672`。

- [ ] **Step 2：实现 Milvus 类型**

参数包含 `storageEndpoint`、`storageSecretName`、`bucketName`、`rootPath`、`storageClass`、`etcdStorageGiB`、`rocksmqStorageGiB`。模板固定：

```yaml
apiVersion: milvus.io/v1beta1
kind: Milvus
metadata:
  name: ${metadata.resourceName}
  namespace: ${metadata.namespace}
  labels: ${metadata.labels}
spec:
  mode: standalone
  components:
    image: milvusdb/milvus:v2.6.16
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: "2"
        memory: 4Gi
  config:
    minio:
      bucketName: ${parameters.bucketName}
      rootPath: ${parameters.rootPath}
      useSSL: false
  dependencies:
    msgStreamType: rocksmq
    rocksmq:
      persistence:
        enabled: true
        pvcDeletion: false
        persistentVolumeClaim:
          spec:
            accessModes: [ReadWriteOnce]
            storageClassName: ${parameters.storageClass}
            resources:
              requests:
                storage: "${string(parameters.rocksmqStorageGiB) + 'Gi'}"
    etcd:
      inCluster:
        deletionPolicy: Retain
        pvcDeletion: false
        values:
          replicaCount: 1
          persistence:
            enabled: true
            storageClass: ${parameters.storageClass}
            size: "${string(parameters.etcdStorageGiB) + 'Gi'}"
    storage:
      external: true
      type: MinIO
      endpoint: ${parameters.storageEndpoint}
      secretRef: ${parameters.storageSecretName}
```

就绪条件：

```yaml
readyWhen: '${has(applied.milvus.status.status) && applied.milvus.status.status == "Healthy"}'
```

输出 `endpoint` 和端口 `19530`。

- [ ] **Step 3：注册两个文件并做 Server-Side Dry Run**

```bash
kubectl apply --server-side --dry-run=server \
  -f platform/openchoreo/resources/cluster-resource-type-rabbitmq.yaml >/dev/null
kubectl apply --server-side --dry-run=server \
  -f platform/openchoreo/resources/cluster-resource-type-milvus.yaml >/dev/null
kustomize build platform/openchoreo/resources >/dev/null
```

Expected: exit 0。

## Task 6：创建 Resource、Binding 与文档

**Files:**
- Create: `platform/openchoreo/agent-platform/resources.yaml`
- Create: `platform/openchoreo/agent-platform/resource-bindings.yaml`
- Modify: `platform/openchoreo/agent-platform/kustomization.yaml`
- Modify: `platform/openchoreo/agent-platform/README.md`
- Modify: `platform/openchoreo/resources/README.md`
- Modify: `README.md`

- [ ] **Step 1：创建三个 Resource**

`resources.yaml` 使用三个 YAML 文档：

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: Resource
metadata:
  name: minio
  namespace: agent-platform
spec:
  owner:
    projectName: agent-platform
  type:
    kind: ClusterResourceType
    name: minio
  parameters:
    secretPath: agent-platform/development/minio
    storageClass: nfs-shared
    storageGiB: 20
---
apiVersion: openchoreo.dev/v1alpha1
kind: Resource
metadata:
  name: rabbitmq
  namespace: agent-platform
spec:
  owner:
    projectName: agent-platform
  type:
    kind: ClusterResourceType
    name: rabbitmq
  parameters:
    replicas: 1
    storageClass: local-path
    storageGiB: 10
---
apiVersion: openchoreo.dev/v1alpha1
kind: Resource
metadata:
  name: milvus
  namespace: agent-platform
spec:
  owner:
    projectName: agent-platform
  type:
    kind: ClusterResourceType
    name: milvus
  parameters:
    storageEndpoint: minio:9000
    storageSecretName: minio-creds
    bucketName: milvus
    rootPath: agent-platform
    storageClass: local-path
    etcdStorageGiB: 10
    rocksmqStorageGiB: 10
```

- [ ] **Step 2：创建未固定的 development Binding**

每个文档使用：

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: ResourceReleaseBinding
metadata:
  name: minio-development
  namespace: agent-platform
spec:
  owner:
    projectName: agent-platform
    resourceName: minio
  environment: development
  retainPolicy: Retain
```

RabbitMQ、Milvus 分别替换 metadata.name 和 resourceName；初次提交不得出现 `resourceRelease`。

- [ ] **Step 3：更新 Kustomization 与 README 索引**

在 Agent Platform Kustomization 的 Project 后添加：

```yaml
  - resources.yaml
  - resource-bindings.yaml
```

README 说明：MinIO 和 RabbitMQ 可先固定，Milvus 必须等待 MinIO Ready；Release pin 是 GitOps 事实来源；密码只来自 OpenBao。

- [ ] **Step 4：运行资源合同并确认 GREEN**

```bash
chmod +x scripts/verify/agent-platform-resources.sh
bash scripts/verify/agent-platform-resources.sh
```

Expected: `Agent Platform managed resources contract: PASS`。

## Task 7：接入完整验证并提交初始声明

**Files:**
- Modify: `scripts/verify/agent-platform-foundation.sh`
- Modify: `README.md`

- [ ] **Step 1：把资源测试加入聚合入口**

在 control-plane 验证之后加入：

```bash
bash scripts/verify/agent-platform-resources.sh
```

- [ ] **Step 2：运行完整本地验证**

```bash
bash scripts/verify/agent-platform-foundation.sh
bash scripts/verify/secrets.sh
git diff --check
git status --short
```

Expected: 所有验证 exit 0；只有当前任务文件变化；没有 `.private` 文件出现在 Git 状态中。

- [ ] **Step 3：提交 GitOps 初始声明**

```bash
git add README.md \
  platform/openchoreo/resources/README.md \
  platform/openchoreo/resources/kustomization.yaml \
  platform/openchoreo/resources/cluster-resource-type-minio.yaml \
  platform/openchoreo/resources/cluster-resource-type-rabbitmq.yaml \
  platform/openchoreo/resources/cluster-resource-type-milvus.yaml \
  platform/openchoreo/agent-platform/README.md \
  platform/openchoreo/agent-platform/kustomization.yaml \
  platform/openchoreo/agent-platform/resources.yaml \
  platform/openchoreo/agent-platform/resource-bindings.yaml \
  scripts/verify/agent-platform-resources.sh \
  scripts/verify/agent-platform-foundation.sh
git commit -s -m "feat: define Agent Platform managed resources"
```

## Task 8：执行受控远程写入并生成 ResourceRelease

**Files:**
- Create locally: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/.private/openbao/agent-platform.env`
- Create after execution: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/logs/2026-07-15-agent-platform-secrets.md`
- Modify: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/logs/README.md`

- [ ] **Step 1：在执行前请求新的明确确认**

明确列出两项远程写入并暂停：

1. 把本地 MinIO 凭据写入 OpenBao。
2. 推送 GitOps `main`，让 Argo CD 创建 ClusterResourceType、Resource 和未固定 Binding。

Expected: 用户在此执行点明确回复确认；此前设计确认不能替代这一确认。

- [ ] **Step 2：生成本地文件并验证忽略与权限**

```bash
cd /Users/yangyongxiang/Desktop/code/github/openchoreo-infra
./scripts/prepare/agent-platform-secrets.sh
git check-ignore -q .private/openbao/agent-platform.env
case "$(uname -s)" in
  Darwin) test "$(stat -f '%Lp' .private/openbao/agent-platform.env)" = 600 ;;
  Linux) test "$(stat -c '%a' .private/openbao/agent-platform.env)" = 600 ;;
esac
```

- [ ] **Step 3：写入 OpenBao 并只检查键存在**

```bash
./scripts/bootstrap/initialize-agent-platform-secrets.sh
```

然后通过脚本自身的 `jq -e` 结果确认两个字段非空；禁止运行会把 Secret 值打印到终端的命令。

- [ ] **Step 4：立即写入脱敏操作记录**

使用 `apply_patch` 创建 `logs/2026-07-15-agent-platform-secrets.md` 并更新 `logs/README.md`。记录适用集群 `homelab`、OpenBao 路径、执行时间、脚本名、字段存在性和初始化结果；不得记录用户名、密码、Token、Secret 数据或 kubeconfig 内容。提交：

```bash
git add logs/README.md logs/2026-07-15-agent-platform-secrets.md
git commit -s -m "docs: record Agent Platform secret initialization"
```

- [ ] **Step 5：合并并推送基础设施脚本及记录**

```bash
git switch main
git merge --ff-only codex/agent-platform-managed-resources
git push origin main
```

- [ ] **Step 6：推送 GitOps 初始声明**

```bash
cd /Users/yangyongxiang/Desktop/code/github/openchoreo-gitops
git switch main
git merge --ff-only codex/agent-platform-managed-resources
git push origin main
```

- [ ] **Step 7：等待 Argo 与 ResourceRelease**

```bash
export KUBECONFIG=/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/.private/kubeconfigs/homelab-admin.yaml
kubectl -n argocd wait application/openchoreo-environments \
  --for=jsonpath='{.status.sync.status}'=Synced --timeout=10m
kubectl -n argocd wait application/agent-platform-control-plane \
  --for=jsonpath='{.status.sync.status}'=Synced --timeout=10m
kubectl -n agent-platform wait resource/minio --for=condition=Ready --timeout=5m
kubectl -n agent-platform wait resource/rabbitmq --for=condition=Ready --timeout=5m
kubectl -n agent-platform wait resource/milvus --for=condition=Ready --timeout=5m
kubectl -n agent-platform get resourcereleases -o wide
```

Expected: 三个 Resource Ready 并各生成一个 ResourceRelease；三个 Binding 仍未固定，尚不创建数据平面实例。

## Task 9：固定 MinIO 与 RabbitMQ Release

**Files:**
- Modify: `platform/openchoreo/agent-platform/resource-bindings.yaml`

- [ ] **Step 1：读取实际 Release 名称并机械写回 Binding**

```bash
release_json="$(kubectl -n agent-platform get resourcereleases -o json)"
minio_release="$(printf '%s' "$release_json" | jq -er '.items | map(select(.spec.owner.resourceName == "minio")) | sort_by(.metadata.creationTimestamp) | last.metadata.name')"
rabbitmq_release="$(printf '%s' "$release_json" | jq -er '.items | map(select(.spec.owner.resourceName == "rabbitmq")) | sort_by(.metadata.creationTimestamp) | last.metadata.name')"
test "$minio_release" = "minio-${minio_release#minio-}"
test "$rabbitmq_release" = "rabbitmq-${rabbitmq_release#rabbitmq-}"
```

使用下面的机械更新把经过验证的运行时值写入对应 Binding：

```bash
MINIO_RELEASE="$minio_release" RABBITMQ_RELEASE="$rabbitmq_release" ruby -ryaml -e '
path = "platform/openchoreo/agent-platform/resource-bindings.yaml"
pins = {
  "minio" => ENV.fetch("MINIO_RELEASE"),
  "rabbitmq" => ENV.fetch("RABBITMQ_RELEASE")
}
docs = YAML.load_stream(File.read(path))
docs.each do |doc|
  resource = doc.dig("spec", "owner", "resourceName")
  doc["spec"]["resourceRelease"] = pins.fetch(resource) if pins.key?(resource)
end
File.write(path, docs.map { |doc| YAML.dump(doc) }.join)
'
```

运行 `git diff`，确认 Milvus Binding 仍未出现 `resourceRelease`。

- [ ] **Step 2：验证、提交并推送**

```bash
bash scripts/verify/agent-platform-foundation.sh
git add platform/openchoreo/agent-platform/resource-bindings.yaml
git commit -s -m "chore: promote MinIO and RabbitMQ development resources"
git push origin main
```

- [ ] **Step 3：等待两个 Binding Ready**

```bash
kubectl -n agent-platform wait resourcereleasebinding/minio-development \
  --for=condition=Ready --timeout=20m
kubectl -n agent-platform wait resourcereleasebinding/rabbitmq-development \
  --for=condition=Ready --timeout=20m
kubectl -n agent-platform get resourcereleasebinding minio-development rabbitmq-development -o wide
```

检查 MinIO StatefulSet、Bucket Job、RabbitmqCluster 和 PVC；不得删除失败资源。

- [ ] **Step 4：验证 Bucket 与 RabbitMQ 状态**

从 MinIO Binding status 取得数据平面 Namespace 和输出，仅使用 Secret 引用启动一次性 `mc` 验证 Pod；命令只打印 Bucket 名称。RabbitMQ 必须满足 `AllReplicasReady=True`、`ClusterAvailable=True`，默认用户 Secret 存在但不读取值。

## Task 10：固定 Milvus Release

**Files:**
- Modify: `platform/openchoreo/agent-platform/resource-bindings.yaml`

- [ ] **Step 1：取得 Milvus Release 并写回 Binding**

```bash
milvus_release="$(kubectl -n agent-platform get resourcereleases -o json | jq -er '.items | map(select(.spec.owner.resourceName == "milvus")) | sort_by(.metadata.creationTimestamp) | last.metadata.name')"
test "$milvus_release" = "milvus-${milvus_release#milvus-}"
```

使用下面的机械更新给 `milvus-development` 写入经过验证的实际 Release：

```bash
MILVUS_RELEASE="$milvus_release" ruby -ryaml -e '
path = "platform/openchoreo/agent-platform/resource-bindings.yaml"
docs = YAML.load_stream(File.read(path))
docs.each do |doc|
  next unless doc.dig("spec", "owner", "resourceName") == "milvus"
  doc["spec"]["resourceRelease"] = ENV.fetch("MILVUS_RELEASE")
end
File.write(path, docs.map { |doc| YAML.dump(doc) }.join)
'
```

- [ ] **Step 2：验证、提交并推送**

```bash
bash scripts/verify/agent-platform-foundation.sh
git add platform/openchoreo/agent-platform/resource-bindings.yaml
git commit -s -m "chore: promote Milvus development resource"
git push origin main
```

- [ ] **Step 3：等待 Milvus Ready**

```bash
kubectl -n agent-platform wait resourcereleasebinding/milvus-development \
  --for=condition=Ready --timeout=30m
kubectl get milvus -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.status,ENDPOINT:.status.endpoint,IMAGE:.status.currentImage'
```

Expected: status `Healthy`，镜像 `milvusdb/milvus:v2.6.16`，Endpoint 非空。

## Task 11：最终验收、日志与收尾

**Files:**
- Modify: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/logs/2026-07-15-agent-platform-secrets.md`

- [ ] **Step 1：运行 GitOps 最终验收**

```bash
cd /Users/yangyongxiang/Desktop/code/github/openchoreo-gitops
bash scripts/verify/agent-platform-foundation.sh
kubectl -n argocd get application homelab-root openchoreo-environments \
  agent-platform-control-plane rabbitmq-cluster-operator milvus-operator \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision'
kubectl -n agent-platform get resources,resourcereleases,resourcereleasebindings
kubectl get rabbitmqcluster,milvus,pod,pvc -A | grep -E 'rabbitmq|milvus|minio|NAMESPACE'
```

Expected: 所有目标 Argo 应用 `Synced/Healthy`；三个 Binding Ready；Pod Ready；PVC 容量和 StorageClass 与设计一致。

- [ ] **Step 2：运行基础设施最终门禁**

```bash
cd /Users/yangyongxiang/Desktop/code/github/openchoreo-infra
REQUIRE_GITLEAKS=1 ./scripts/verify/phase01.sh
git check-ignore -q .private/openbao/agent-platform.env
git status --short --branch
```

- [ ] **Step 3：补充最终脱敏验收结果**

在既有记录中追加 ExternalSecret Ready、三个 Binding 状态、回滚方式和后续风险。不得记录用户名、密码、Token、Secret 数据或 kubeconfig 内容。提交：

```bash
git add logs/2026-07-15-agent-platform-secrets.md
git commit -s -m "docs: complete Agent Platform resource acceptance"
git push origin main
```

- [ ] **Step 4：确认两个仓库干净且远端一致**

```bash
git -C /Users/yangyongxiang/Desktop/code/github/openchoreo-infra status --short --branch
git -C /Users/yangyongxiang/Desktop/code/github/openchoreo-gitops status --short --branch
git -C /Users/yangyongxiang/Desktop/code/github/openchoreo-infra rev-parse HEAD
git -C /Users/yangyongxiang/Desktop/code/github/openchoreo-infra rev-parse origin/main
git -C /Users/yangyongxiang/Desktop/code/github/openchoreo-gitops rev-parse HEAD
git -C /Users/yangyongxiang/Desktop/code/github/openchoreo-gitops rev-parse origin/main
```

Expected: 两个仓库均无本任务未提交内容，HEAD 等于 `origin/main`；本地 `.private` 文件继续被忽略。
