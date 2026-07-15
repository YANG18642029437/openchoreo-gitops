# OpenChoreo 1.1.2 资源边界

本目录只使用当前 OpenChoreo 1.1.2 控制平面已经提供的 API。

- `DeploymentPipeline` 表达 Development → Staging → Production 的晋级拓扑。
- `Environment.spec.isProduction: true` 标记生产环境。1.1.2 没有声明式人工审批或自动晋级字段，因此晋级仍是显式 Release 操作。
- 数据平面控制器在 Project 协调后创建 workload cell Namespace。Secret 始终只存在于对应 Namespace，不复制到 Git。
- 当前版本不提供 `ClusterProjectType`；Namespace 配额、ServiceAccount 和基础 NetworkPolicy 需要在 cell Namespace 创建后附加，或等升级到支持项目模板的版本再统一声明。

## Agent Platform 资源类型

- `minio`：OpenChoreo 直接渲染 ExternalSecret、Service、单副本 StatefulSet/PVC 和 Bucket 初始化 Job；持久卷使用 `nfs-shared`。
- `rabbitmq`：OpenChoreo 渲染 `RabbitmqCluster`，实际生命周期由 RabbitMQ Cluster Operator 管理；开发环境固定单副本和 `local-path`。
- `milvus`：OpenChoreo 渲染 standalone `Milvus`，实际生命周期由 Milvus Operator 管理；对象存储复用 MinIO，etcd 与 RocksMQ 使用 `local-path`。

三个类型的持久化数据均使用 `Retain` 语义。ResourceType 只描述可复用能力，具体开发环境参数和 Release 固定状态位于 `../agent-platform/`。
