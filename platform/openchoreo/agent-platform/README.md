# Agent Platform OpenChoreo Resources

本目录保存 Agent Platform 在 OpenChoreo 控制平面的 namespaced 资源，当前只包含 `development` Environment、`development-only` DeploymentPipeline 和 `agent-platform` Project。

五类共享中间件由集群级 `ClusterResourceType` 提供，Resource 与 ResourceReleaseBinding 后续仍写入本目录；底层 Operator、RBAC 和 ResourceType 不放入业务 Namespace。

应用顺序：Namespace → Environment → DeploymentPipeline → Project → Resource → 未固定 ResourceReleaseBinding → 固定 ResourceReleaseBinding。持久化资源统一使用 `retainPolicy: Retain`。

本目录不得写入密码、Token、kubeconfig 或 Secret 明文。
