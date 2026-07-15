# Agent Platform OpenChoreo Resources

本目录保存 Agent Platform 在 OpenChoreo 控制平面的 namespaced 资源，包括 `development` Environment、`development-only` DeploymentPipeline、`agent-platform` Project，以及 PostgreSQL、Redis、MinIO、RabbitMQ、Milvus 五个共享资源申请。

共享中间件由集群级 `ClusterResourceType` 提供，Resource 与 ResourceReleaseBinding 写在本目录；底层 Operator、RBAC 和 ResourceType 不放入业务 Namespace。

应用顺序：Namespace → Environment → DeploymentPipeline → Project → Resource → 未固定 ResourceReleaseBinding → 固定 ResourceReleaseBinding。持久化资源统一使用 `retainPolicy: Retain`。

首次创建 Resource 后，OpenChoreo 会生成 ResourceRelease。ResourceReleaseBinding 必须把集群实际生成的 Release 名称写回 Git，Git 才是 development 发布状态的事实来源。MinIO 与 RabbitMQ 可以先固定；Milvus 依赖 MinIO 的 Service、凭据和 `milvus` Bucket，必须在 MinIO Ready 后再固定。

MinIO 与 Redis 密码分别由 OpenBao 的 `openchoreo/agent-platform/development/minio`、`openchoreo/agent-platform/development/redis` 提供，并通过 External Secrets Operator 同步到数据平面。PostgreSQL 应用凭据由 CloudNativePG 生成。本目录不得写入密码、Token、kubeconfig 或 Secret 明文。
