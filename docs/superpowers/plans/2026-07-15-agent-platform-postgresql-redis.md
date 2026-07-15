# Agent Platform PostgreSQL 与 Redis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Agent Platform development 环境通过 OpenChoreo 创建单实例 PostgreSQL 与 Redis，并完成凭据、持久化、Release 固定和在线功能验收。

**Architecture:** PostgreSQL 复用现有 ClusterResourceType、Crossplane XPostgreSQL 和 CloudNativePG；Redis 由新 ClusterResourceType 直接渲染 ExternalSecret、Service、StatefulSet 和 PVC。Redis 密码从本地私有文件同步至 OpenBao，PostgreSQL 凭据由 CloudNativePG 生成。

**Tech Stack:** OpenChoreo 1.1.2、Argo CD、Crossplane、CloudNativePG、External Secrets Operator、OpenBao、PostgreSQL、Redis 8.2.7、Kustomize、Bash

---

### Task 1: 扩展 Redis 本地凭据合同

**Files:**
- Modify: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/scripts/verify/agent-platform-secrets.sh`
- Modify: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/scripts/prepare/agent-platform-secrets.sh`
- Modify: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/scripts/bootstrap/initialize-agent-platform-secrets.sh`

- [ ] **Step 1: 写入失败合同**

在验证脚本中要求本地文件存在 `REDIS_PASSWORD`、长度不少于 32，并要求初始化脚本包含 `openchoreo/agent-platform/development/redis` 和 `password` 属性。

- [ ] **Step 2: 验证 RED**

Run:

```bash
bash scripts/verify/agent-platform-secrets.sh
```

Expected: 因现有脚本尚未生成或同步 Redis 密码而失败。

- [ ] **Step 3: 最小实现**

准备脚本在变量缺失时生成 `REDIS_PASSWORD` 并保持已有 MinIO 值不变；初始化脚本幂等写入 Redis OpenBao 路径，并只验证类型和长度。

- [ ] **Step 4: 验证 GREEN**

Run:

```bash
bash -n scripts/prepare/agent-platform-secrets.sh
bash -n scripts/bootstrap/initialize-agent-platform-secrets.sh
bash scripts/verify/agent-platform-secrets.sh
```

Expected: `Agent Platform local secret contract: PASS`。

- [ ] **Step 5: 提交**

```bash
git add scripts/verify/agent-platform-secrets.sh \
  scripts/prepare/agent-platform-secrets.sh \
  scripts/bootstrap/initialize-agent-platform-secrets.sh
git commit -m "feat: manage Agent Platform Redis secret"
```

### Task 2: 定义 PostgreSQL 与 Redis 资源合同

**Files:**
- Modify: `scripts/verify/agent-platform-resources.sh`
- Modify: `platform/openchoreo/resources/cluster-resource-type-postgresql.yaml`
- Create: `platform/openchoreo/resources/cluster-resource-type-redis.yaml`
- Modify: `platform/openchoreo/resources/kustomization.yaml`

- [ ] **Step 1: 写入失败合同**

验证脚本要求 Redis 类型包含 `redis:8.2.7-alpine`、ExternalSecret、AOF、认证探针、单副本和 `Retain`；同时要求 PostgreSQL 类型为 `Retain`。

- [ ] **Step 2: 验证 RED**

Run:

```bash
KUBECONFIG=../openchoreo-infra/.private/kubeconfigs/homelab-admin.yaml \
  bash scripts/verify/agent-platform-resources.sh
```

Expected: Redis ClusterResourceType 不存在而失败。

- [ ] **Step 3: 最小实现**

Redis 类型渲染 `ExternalSecret`、`Service` 和单副本 `StatefulSet`；PVC 使用参数化 `local-path/10Gi`，Secret 内生成 `redis.conf`，探针使用 `REDISCLI_AUTH`。把 PostgreSQL `retainPolicy` 改为 `Retain`。

- [ ] **Step 4: 验证 GREEN**

Run:

```bash
KUBECONFIG=../openchoreo-infra/.private/kubeconfigs/homelab-admin.yaml \
  bash scripts/verify/agent-platform-resources.sh
```

Expected: `Agent Platform managed resources contract: PASS`。

### Task 3: 创建 development Resource

**Files:**
- Modify: `platform/openchoreo/agent-platform/resources.yaml`
- Modify: `platform/openchoreo/agent-platform/resource-bindings.yaml`
- Modify: `platform/openchoreo/agent-platform/README.md`
- Modify: `platform/openchoreo/resources/README.md`
- Modify: `README.md`

- [ ] **Step 1: 添加 PostgreSQL Resource**

参数固定为 `databaseName: agent_platform`、`instances: 1`、`storageGiB: 10`。

- [ ] **Step 2: 添加 Redis Resource**

参数固定为 `secretPath: agent-platform/development/redis`、`storageClass: local-path`、`storageGiB: 10`。

- [ ] **Step 3: 添加未固定 Binding**

先创建 `postgresql-development` 和 `redis-development`，暂不写不存在的 Release 名称；等控制面生成后再固定。

- [ ] **Step 4: 更新说明并验证**

Run:

```bash
KUBECONFIG=../openchoreo-infra/.private/kubeconfigs/homelab-admin.yaml \
  bash scripts/verify/agent-platform-foundation.sh
```

Expected: 全部本地合同通过。

- [ ] **Step 5: 提交 GitOps 声明**

```bash
git add scripts/verify/agent-platform-resources.sh \
  platform/openchoreo/resources/cluster-resource-type-postgresql.yaml \
  platform/openchoreo/resources/cluster-resource-type-redis.yaml \
  platform/openchoreo/resources/kustomization.yaml \
  platform/openchoreo/resources/README.md \
  platform/openchoreo/agent-platform/resources.yaml \
  platform/openchoreo/agent-platform/resource-bindings.yaml \
  platform/openchoreo/agent-platform/README.md README.md
git commit -m "feat: define Agent Platform PostgreSQL and Redis"
```

### Task 4: 初始化 Redis OpenBao Secret 并发布

**Files:**
- Protected local file: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/.private/openbao/agent-platform.env`
- Modify: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/logs/2026-07-15-agent-platform-secrets.md`

- [ ] **Step 1: 生成缺失的 Redis 密码**

```bash
./scripts/prepare/agent-platform-secrets.sh
```

Expected: 不输出密码，文件权限保持 `0600`。

- [ ] **Step 2: 同步 OpenBao**

```bash
./scripts/bootstrap/initialize-agent-platform-secrets.sh
```

Expected: `Agent Platform OpenBao secret initialization: PASS`。

- [ ] **Step 3: 运行 infra 门禁并推送两个仓库**

```bash
REQUIRE_GITLEAKS=1 ./scripts/verify/phase01.sh
git push origin main
```

Expected: 无 Secret 泄漏，两个 main 推送成功。

### Task 5: 固定 Release 并在线验收

**Files:**
- Modify: `platform/openchoreo/agent-platform/resource-bindings.yaml`
- Modify: `/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/logs/2026-07-15-agent-platform-secrets.md`
- Create: `/Users/yangyongxiang/Desktop/skills/remote-service/data/software/openchoreo-homelab/postgresql-redis-development-2026-07-15.md`
- Create: `/Users/yangyongxiang/Desktop/skills/remote-service/data/software/openchoreo-homelab/README.md`
- Modify: `/Users/yangyongxiang/Desktop/skills/remote-service/data/software/README.md`

- [ ] **Step 1: 获取并固定实际 Release**

从 `agent-platform` Namespace 中选择 PostgreSQL 与 Redis 最新 ResourceRelease，把实际名称写入对应 Binding，提交并推送。

- [ ] **Step 2: 等待 Ready**

```bash
kubectl -n agent-platform wait resourcereleasebinding/postgresql-development \
  --for=condition=Ready --timeout=15m
kubectl -n agent-platform wait resourcereleasebinding/redis-development \
  --for=condition=Ready --timeout=15m
```

Expected: 两个 Binding condition met。

- [ ] **Step 3: 功能验证**

通过数据面 Secret 在 Pod 内执行 PostgreSQL `SELECT 1`；Redis 验证未认证请求被拒绝、认证 `PING` 返回 `PONG`。命令和日志不得打印密码。

- [ ] **Step 4: 记录验收结果**

只记录资源名称、镜像、Ready 状态、PVC 容量、Release 名称和功能结果；更新 infra 脱敏日志与 remote-service 软件索引。

- [ ] **Step 5: 最终门禁**

```bash
bash scripts/verify/agent-platform-foundation.sh
REQUIRE_GITLEAKS=1 ./scripts/verify/phase01.sh
```

Expected: 两个仓库门禁通过、工作树干净、本地 HEAD 等于 `origin/main`。
