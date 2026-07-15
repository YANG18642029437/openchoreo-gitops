# Agent Platform PostgreSQL 与 Redis 扩展设计

## 1. 目标

在现有 `agent-platform` Project 的 `development` Environment 中补齐 PostgreSQL 与 Redis，沿用已经验证的 OpenChoreo 发布链路：

`ClusterResourceType → Resource → ResourceRelease → ResourceReleaseBinding → 数据面工作负载`

本阶段只创建 development 单实例，不创建 staging、production、高可用或公网入口。

## 2. 方案选择

采用以下组合：

- PostgreSQL 复用现有 `postgresql` ClusterResourceType，经 Crossplane `XPostgreSQL` 交给 CloudNativePG 管理。
- Redis 新增直接渲染 Kubernetes 原生资源的 `redis` ClusterResourceType。

没有选择“两个服务都直接使用 StatefulSet”，因为仓库已经具备并在线验证了 Crossplane + CloudNativePG PostgreSQL 能力；重复实现 PostgreSQL 生命周期会产生两套备份、升级和 Secret 约定。没有为 Redis额外安装 Operator，因为 development 单实例只需要持久化、认证和健康检查，直接资源合同更小。

## 3. PostgreSQL

- Resource 名称：`postgresql`
- 数据库：`agent_platform`
- 实例数：`1`
- 存储：`10Gi`、`local-path`
- 端口：`5432`
- 管理链路：OpenChoreo → Crossplane → CloudNativePG
- 数据保留：ClusterResourceType 与 ResourceReleaseBinding 都使用 `Retain`

CloudNativePG 初始化数据库和同名应用用户，并把 `dbname`、`username`、`password`、`uri` 写入数据面 Secret。OpenChoreo 输出只保留 Secret 引用，不把明文复制到 Git、控制面文档或日志。

## 4. Redis

- Resource 名称：`redis`
- 镜像：`redis:8.2.7-alpine`
- 副本数：`1`
- 存储：`10Gi`、`local-path`
- 端口：`6379`
- 持久化：AOF，`appendfsync everysec`
- 认证：强制密码
- 数据保留：ClusterResourceType 与 ResourceReleaseBinding 都使用 `Retain`

Redis ClusterResourceType 渲染：

1. `ExternalSecret`：从 OpenBao `agent-platform/development/redis` 读取 `password`。
2. `Service`：提供数据面内稳定 FQDN。
3. 单副本 `StatefulSet`：挂载 `10Gi` PVC 和 Secret 中生成的 `redis.conf`。

Redis 启动参数不包含明文密码。探针通过 Secret 注入的 `REDISCLI_AUTH` 调用 `redis-cli ping`。

## 5. 凭据边界

本地私有文件继续使用：

`openchoreo-infra/.private/openbao/agent-platform.env`

文件新增 `REDIS_PASSWORD`，权限保持 `0600`。初始化脚本幂等写入：

- MinIO：`openchoreo/agent-platform/development/minio`
- Redis：`openchoreo/agent-platform/development/redis`

PostgreSQL 密码由 CloudNativePG 生成，不在本地文件中复制第二份。

## 6. 发布顺序

1. 扩展本地 Secret 合同并同步 Redis 密码到 OpenBao。
2. 发布 PostgreSQL/Redis ClusterResourceType 和 Agent Platform Resource。
3. 等待 OpenChoreo 生成 ResourceRelease。
4. 把实际 Release 名称固定到 Git 中的 ResourceReleaseBinding。
5. 等待 Argo CD 和三个控制器完成协调。

PostgreSQL 与 Redis 互不依赖，可以同时创建；它们不阻塞现有 MinIO、RabbitMQ、Milvus。

## 7. 验收

- `postgresql-development`、`redis-development` 均为 `Ready=True`。
- CloudNativePG Cluster 为 Ready，PostgreSQL Pod `1/1 Ready`，PVC `10Gi Bound`。
- PostgreSQL 最小真实连接执行 `SELECT 1` 成功，但不输出凭据。
- Redis Pod `1/1 Ready`，PVC `10Gi Bound`，认证后的 `PING` 返回 `PONG`。
- Redis 未认证的 `PING` 被拒绝。
- Argo CD 相关应用保持 `Synced/Healthy`。
- GitOps 与 infra 验证脚本、gitleaks 均通过。

## 8. 回滚

回滚 Git 提交只停止继续发布，不删除已有 PVC。ResourceType 与 Binding 的 `Retain` 语义用于保护数据；任何删除 Cluster、StatefulSet、PVC 或 OpenBao Secret 的动作都需要重新取得用户明确确认。
