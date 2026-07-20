# OpenChoreo 1.1.2 资源边界

本目录只使用当前 OpenChoreo 1.1.2 控制平面已经提供的 API。

- `DeploymentPipeline` 表达 Development → Staging → Production 的晋级拓扑。
- `Environment.spec.isProduction: true` 标记生产环境。1.1.2 没有声明式人工审批或自动晋级字段，因此晋级仍是显式 Release 操作。
- 数据平面控制器在 Project 协调后创建 workload cell Namespace。Secret 始终只存在于对应 Namespace，不复制到 Git。
- 当前版本不提供 `ClusterProjectType`；Namespace 配额、ServiceAccount 和基础 NetworkPolicy 需要在 cell Namespace 创建后附加，或等升级到支持项目模板的版本再统一声明。

## Agent Platform 资源类型

- `postgresql`：OpenChoreo 渲染 Crossplane `XPostgreSQL`，由 CloudNativePG 管理单实例数据库、PVC 和应用 Secret；development 使用 `local-path`。
- `minio`：OpenChoreo 直接渲染 ExternalSecret、Service、单副本 StatefulSet/PVC 和 Bucket 初始化 Job；持久卷使用 `nfs-shared`。
- `rabbitmq`：OpenChoreo 渲染 `RabbitmqCluster`，实际生命周期由 RabbitMQ Cluster Operator 管理；开发环境固定单副本和 `local-path`。连接输出使用 Operator 的确定性 Service/Secret 名称，就绪状态由 OpenChoreo 管理的 AMQP TCP 探测 Job 判断，避免依赖自定义 CR 状态透传。
- `milvus`：OpenChoreo 渲染 standalone `Milvus`，实际生命周期由 Milvus Operator 管理；对象存储复用 MinIO，ResourceType 会用数据平面 Namespace 生成 MinIO 完整集群 FQDN，确保 Operator 能跨 Namespace 检查存储；etcd 与 RocksMQ 使用 `local-path`。
- `redis`：OpenChoreo 直接渲染 ExternalSecret、Service 和单副本 StatefulSet/PVC；默认用户保持 RAG 兼容，Langfuse 使用独立 ACL 用户与逻辑 DB 1，密码来自 OpenBao，启用 AOF，development 使用 `local-path`。逻辑 DB 只提供命名空间隔离，不是强安全边界。
- `clickhouse`：OpenChoreo 直接渲染 ExternalSecret、UTC 配置、Service 和单副本 StatefulSet/PVC；仅供 Langfuse development 分析存储，关闭集群模式并使用 `local-path`。
- `langfuse`：以官方 Helm Chart `1.5.39` / Langfuse `3.212.0` 为渲染基线，由 OpenChoreo 直接管理幂等 PostgreSQL/MinIO bootstrap、单副本 Web/Worker 和 Service；四个内置依赖全部关闭，镜像固定多架构 Digest，遥测、公开注册和实验功能默认关闭。

七个类型的持久化数据均使用 `Retain` 语义。ResourceType 只描述可复用能力，具体开发环境参数和 Release 固定状态位于 `../agent-platform/`。

PostgreSQL Cluster 显式生成受控 superuser Secret，仅供 Langfuse bootstrap Job 幂等创建独立 role/database；应用 Pod 不读取该 Secret。MinIO 现有 RAG bucket 与 root 凭据保持不变，Langfuse bootstrap 创建专用用户，并只授权 `langfuse-events`、`langfuse-media`、`langfuse-exports`。Chart 基线和验证入口位于 `tests/langfuse-chart-1.5.39-values.yaml`、`tests/verify-langfuse-chart-baseline.sh`，只包含虚构 Secret 引用。
