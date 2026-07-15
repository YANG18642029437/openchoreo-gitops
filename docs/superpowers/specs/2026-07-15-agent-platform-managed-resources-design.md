# Agent Platform 开发环境托管资源设计

## 1. 背景

Agent Platform 需要在 OpenChoreo `agent-platform` Project 的 `development` Environment 中创建知识库与 Agent 基础设施。平台已经安装 RabbitMQ Cluster Operator、Milvus Operator、External Secrets Operator、OpenBao 和 OpenChoreo 1.1.2，并已创建开发环境、单环境部署流水线和 Project。

本设计补齐 MinIO、RabbitMQ、Milvus 的 OpenChoreo 资源入口和实际开发实例。业务资源统一从 `ClusterResourceType`、`Resource`、`ResourceRelease`、`ResourceReleaseBinding` 链路进入数据平面；RabbitMQ 与 Milvus 的复杂生命周期继续交给各自 Operator，单节点 MinIO 由 OpenChoreo Resource Operator 直接渲染 Kubernetes 资源。

## 2. 目标

- 注册 `minio`、`rabbitmq`、`milvus` 三个集群级 `ClusterResourceType`。
- 在 `agent-platform` Project 中创建三个 `Resource`，并绑定到 `development` Environment。
- 创建单副本 MinIO、单副本 RabbitMQ 和 standalone Milvus 实例。
- 让 Milvus 使用共享 MinIO，而不是由 Milvus Operator 创建专用 MinIO。
- 在共享 MinIO 中初始化 `milvus` 与 `knowledge-base` Bucket。
- 密码只保存在本机私有目录和 OpenBao，不写入 Git，不在脚本输出中显示。
- 所有持久化 ResourceBinding 使用 `retainPolicy: Retain`。
- 通过契约测试、Server-Side Dry Run、Argo CD 状态和运行时探测完成验收。

## 3. 非目标

- 本阶段不创建 staging 或 production 实例。
- 本阶段不配置高可用副本、跨节点 MinIO、RabbitMQ 三节点集群或 Milvus cluster 模式。
- 本阶段不开放 MinIO、RabbitMQ、Milvus 的公网入口。
- 本阶段不实现备份恢复自动化、容量自动扩缩容或生产级灾难恢复。
- 本阶段不创建 RAG、Agent、MCP Gateway 的应用 Deployment。
- 本阶段不引入 MinIO Operator；生产环境是否使用 MinIO Operator 在生产资源设计中重新评估。

## 4. 分层架构

```text
Argo CD
  ├── OpenChoreo ClusterResourceType/minio
  ├── OpenChoreo ClusterResourceType/rabbitmq
  ├── OpenChoreo ClusterResourceType/milvus
  └── agent-platform namespaced resources
       ├── Resource/minio
       ├── Resource/rabbitmq
       ├── Resource/milvus
       └── development ResourceReleaseBindings
                    │
                    ▼
OpenChoreo Resource Operator
  ├── MinIO Service / StatefulSet / PVC / ExternalSecret / Bucket Job
  ├── RabbitmqCluster CR ──► RabbitMQ Cluster Operator
  └── Milvus CR ──────────► Milvus Operator
                                 ├── standalone Milvus
                                 ├── single-replica etcd
                                 └── persistent RocksMQ
```

Argo CD 管理平台声明，OpenChoreo 管理业务资源发布和环境绑定，RabbitMQ/Milvus Operator 管理具体中间件实例。Operator 属于平台执行层，不是 OpenChoreo 的替代品。

## 5. 资源合同

| Resource | ClusterResourceType | 开发环境实例 | 稳定依赖名称 | 保留策略 |
|---|---|---|---|---|
| `minio` | `minio` | 单副本 StatefulSet | `minio:9000`、`minio-creds` | `Retain` |
| `rabbitmq` | `rabbitmq` | 单副本 RabbitmqCluster | Operator 状态输出 | `Retain` |
| `milvus` | `milvus` | standalone Milvus | `minio:9000`、`minio-creds` | `Retain` |

同一 Project 和 Environment 的 Resource 会渲染到同一个数据平面 Cell Namespace。MinIO 使用 `metadata.resourceName` 形成稳定的 `minio` Service 与 `minio-creds` Secret，Milvus Resource 参数引用这组名称。此命名合同只允许同一 Project/Environment 创建一个名为 `minio` 的共享对象存储实例。

## 6. MinIO 设计

### 6.1 资源内容

`ClusterResourceType/minio` 直接渲染：

- `ExternalSecret/minio-creds`：从 OpenBao 读取凭据。
- `Service/minio`：内部端口 `9000`，控制台端口 `9001`。
- `StatefulSet/minio`：单副本 MinIO Server。
- `volumeClaimTemplates`：`nfs-shared`、`20Gi`。
- Bucket 初始化 Job：幂等创建 `milvus` 和 `knowledge-base`。

镜像固定为：

- Server：`quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z`
- Client：`quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z`

两个镜像在设计阶段已通过 OCI Manifest 检查。

### 6.2 凭据 Secret

OpenBao 保存 `root_user` 和 `root_password`。ExternalSecret 在数据平面生成以下键：

- `MINIO_ROOT_USER`
- `MINIO_ROOT_PASSWORD`
- `accesskey`
- `secretkey`

前两个键供 MinIO 容器使用，后两个键符合 Milvus Operator 外部对象存储的 Secret 合同。Secret 值不会进入 OpenChoreo 控制平面；ResourceType 输出 Secret 名称、Service 主机名、端口，以及指向 `accesskey`、`secretkey` 的 `secretKeyRef`，供后续 RAG Workload 通过 Resource Dependency 安全绑定。

### 6.3 就绪条件

MinIO ResourceReleaseBinding 只有同时满足以下条件才 Ready：

- StatefulSet 的 `readyReplicas` 等于 `replicas`，且副本数大于零。
- Bucket 初始化 Job 的 `succeeded` 大于零。
- ExternalSecret 已生成目标 Secret；若 OpenBao 不可用，StatefulSet 不会获得凭据，Binding 保持未就绪。

## 7. RabbitMQ 设计

`ClusterResourceType/rabbitmq` 渲染 `rabbitmq.com/v1beta1` 的 `RabbitmqCluster`：

- 名称：`rabbitmq`
- 副本数：`1`
- 镜像：`rabbitmq:4.2.6-management`
- 存储：`local-path`、`10Gi`
- 请求：`250m CPU / 512Mi memory`
- 上限：`1 CPU / 2Gi memory`

就绪条件读取 RabbitMQ Cluster Operator 的 status conditions，要求所有副本就绪。输出包括 Service 名称、AMQP 端口、默认用户 Secret 名称，以及 Secret 中的 username/password 引用；Secret 明文不返回控制平面。

## 8. Milvus 设计

`ClusterResourceType/milvus` 渲染 `milvus.io/v1beta1` 的 `Milvus`：

- 模式：`standalone`
- 镜像：`milvusdb/milvus:v2.6.16`
- 请求：`500m CPU / 2Gi memory`
- 上限：`2 CPU / 4Gi memory`
- 消息存储：持久化 RocksMQ
- RocksMQ 存储：`local-path`、`10Gi`
- 元数据存储：Milvus Operator 管理的单副本 etcd
- etcd 存储：`local-path`、`10Gi`
- 对象存储：外部 MinIO
- MinIO Endpoint：`minio.<数据面 namespace>.svc.cluster.local:9000`
- MinIO Secret：`minio-creds`
- Bucket：`milvus`
- Root Path：`agent-platform`
- TLS：集群内开发连接暂不启用

Milvus Pod 显式设置 `MINIO_PORT=9000`。这是为了避免 Kubernetes Service Links 自动注入的
`MINIO_PORT=tcp://<ClusterIP>:9000` 覆盖 Milvus 的同名配置键，导致 MinIO SDK 把 endpoint
解析为带路径的非法 URL。跨 namespace FQDN 仍同时供 Milvus Operator 和数据面工作负载访问。

Milvus ResourceReleaseBinding 只在 MinIO Binding 已 Ready 后固定发布。Milvus 就绪条件要求 `status.status` 为 `Healthy`，并输出 Operator 报告的 Endpoint 与标准端口 `19530`。

## 9. 本地凭据与 OpenBao

真实凭据保存在：

```text
/Users/yangyongxiang/Desktop/code/github/openchoreo-infra/.private/openbao/agent-platform.env
```

文件必须包含 `MINIO_ROOT_USER` 和 `MINIO_ROOT_PASSWORD` 两个非空环境变量；真实值不在设计文档、示例文件或终端输出中展示。

`openchoreo-infra/.private/` 已被 Git 忽略。目录权限必须为 `0700`，文件权限必须为 `0600`。

`openchoreo-infra` 增加幂等初始化脚本，读取本地文件后把凭据写入 OpenBao KV v2 路径：

```text
openchoreo/agent-platform/development/minio
```

脚本只输出检查和写入状态，不输出用户名、密码、Token 或 Secret 内容。GitOps 仓库中的 ExternalSecret 只包含 OpenBao key 和 property 名称。

## 10. GitOps 发布顺序

ResourceRelease 名称由 OpenChoreo 根据 Resource 与 ResourceType 快照生成，因此 Binding 采用分阶段固定：

1. 提交三个 ClusterResourceType、三个 Resource 和未设置 `resourceRelease` 的三个 Binding。
2. Argo CD 同步后，等待 OpenChoreo 为三个 Resource 生成 ResourceRelease。
3. 运行本地凭据初始化脚本，确认 OpenBao 中的 MinIO 路径可由 ClusterSecretStore 读取。
4. 将 MinIO 和 RabbitMQ 的实际 ResourceRelease 名称写回 Git，并等待两个 Binding Ready。
5. 验证 MinIO 的两个 Bucket 已创建。
6. 将 Milvus 的实际 ResourceRelease 名称写回 Git，并等待 Milvus Binding Ready。
7. 最终确认 Git 中记录的 Release pin 与集群 status 一致。

Argo CD 可以显示声明已同步但 ResourceReleaseBinding 尚未 Ready。发布脚本和验收流程必须同时检查 Argo CD、OpenChoreo Binding status 和底层 Operator CR status，不能只以 Argo CD `Synced` 判断成功。

## 11. 仓库改动边界

### 11.1 openchoreo-gitops

- 在 `platform/openchoreo/resources/` 增加三个 ClusterResourceType。
- 在 `platform/openchoreo/agent-platform/` 增加 Resource 与 ResourceReleaseBinding。
- 更新两个目录的 Kustomization 和 README。
- 扩展 Agent Platform 验证脚本，覆盖资源合同、敏感信息、镜像、存储、Release pin 和 Server-Side Dry Run。
- 更新根 README 的文件索引与运行边界。

OpenChoreo Data Plane 的基础 ClusterRole 已具备 StatefulSet、Service、PVC、Job、ExternalSecret 和 Password Generator 权限；现有附加 RBAC 继续只补 RabbitMQ 与 Milvus CR 权限。

### 11.2 openchoreo-infra

- 增加 Agent Platform 凭据初始化脚本。
- 增加不含真实值的使用说明和验证脚本。
- 本地创建 `.private/openbao/agent-platform.env`，不提交该文件。
- 更新对应 README/运维索引，记录路径、权限、写入目标和验证命令。

## 12. 失败处理与数据安全

- OpenBao 或 ExternalSecret 不可用：不创建临时默认密码，MinIO 保持 Pending。
- MinIO 不 Ready：停止 Milvus Release pin，不发布 Milvus。
- Bucket Job 失败：保留 PVC，修复 Job 或连接配置后重新发布，不删除 MinIO 数据。
- RabbitMQ 或 Milvus 不 Ready：只修改 ResourceType、Resource 参数或 Operator 配置，不直接修改 Operator 生成的 Deployment/StatefulSet。
- ResourceBinding 删除或发布失败：`retainPolicy: Retain` 保留数据平面资源。
- PVC、Bucket 和数据库内容不得由自动修复脚本删除。
- staging/production 不复用开发凭据、开发 PVC 或开发 Bucket。

## 13. 测试策略

实现采用测试先行：

1. 先扩展 Shell 契约测试，要求三个 ClusterResourceType、三个 Resource、三个 Binding、固定镜像、单实例参数、存储规格和 ExternalSecret 合同存在；测试必须先因文件缺失而失败。
2. 最小实现清单后，运行同一测试确认转绿。
3. 使用 Kustomize 渲染完整 App-of-Apps。
4. 对 ClusterResourceType、Resource 和 Binding 执行 Kubernetes Server-Side Dry Run。
5. 运行凭据泄漏检查、`git diff --check` 和仓库完整验证入口。
6. Argo CD 同步后检查 ResourceRelease 与 ResourceReleaseBinding status。
7. 检查底层 Pod、PVC、RabbitmqCluster 和 Milvus status。
8. 通过 MinIO Client 验证 `milvus` 与 `knowledge-base` Bucket 存在，但不在日志打印凭据。

## 14. 验收标准

- Argo CD 根应用和 Agent Platform 子应用为 `Synced / Healthy`。
- `ClusterResourceType/minio`、`rabbitmq`、`milvus` 已注册。
- 三个 Resource 均为 Ready，并各自生成 ResourceRelease。
- 三个 development ResourceReleaseBinding 均为 Ready，且 Release pin 已写回 Git。
- MinIO、RabbitMQ、Milvus 的运行 Pod Ready 且无持续重启。
- MinIO PVC 为 `20Gi nfs-shared`，RabbitMQ PVC 为 `10Gi local-path`，Milvus etcd/RocksMQ 使用 `10Gi local-path`。
- MinIO 中存在 `milvus` 与 `knowledge-base` Bucket。
- MinIO Binding 输出 `accessKey`、`secretKey` 的数据平面 Secret 引用，不包含明文凭据。
- Milvus status 为 `Healthy`，Endpoint 已生成。
- RabbitMQ status 表明单副本 Ready，默认用户 Secret 已生成。
- 本地凭据文件被 Git 忽略且权限为 `0600`。
- Git 历史、提交差异和操作日志中没有真实凭据。
- 所有静态、Server-Side Dry Run 和运行时验证命令退出码为零。

## 15. 后续演进

- 生产环境改为高可用 RabbitMQ、Milvus cluster 与独立高可用对象存储。
- 为 MinIO 增加异机备份、Bucket 生命周期和容量监控。
- 评估 MinIO Operator 或兼容 S3 服务，但保持 `ClusterResourceType/minio` 的上层输出合同稳定。
- RAG Service 通过 OpenChoreo Workload Resource Dependency 消费 MinIO、Milvus、RabbitMQ 和 PostgreSQL 输出。
- 为 Redis、PostgreSQL 和其余共享能力使用同样的 ResourceRelease/Binding 发布纪律。
