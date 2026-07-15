# OpenChoreo Homelab GitOps

本仓库保存 OpenChoreo homelab Kubernetes 集群的**期望状态**。Argo CD 持续读取本仓库 `main` 分支，并按照这里声明的 Helm Chart、Kustomize 资源、部署顺序和平台配置维护三台 K3s 节点中的系统。

本仓库不负责创建 Proxmox 虚拟机，也不保存密码、SSH 私钥、Kubeconfig 或 Terraform State。虚拟机、磁盘、K3s 安装和敏感文件由同级 `openchoreo-infra` 仓库管理；OpenChoreo 产品源代码位于同级 `openchoreo` 仓库。

## 工作方式

```text
GitHub main 分支
        │
        ▼
bootstrap/root-application.yaml
        │ 创建 homelab-root
        ▼
clusters/homelab/kustomization.yaml
        │ 创建 32 个 Argo CD Application
        ▼
基础设施 → 密钥系统 → Harbor/Thunder → OpenChoreo 四个 Plane
        │
        ▼
可观测性 → Crossplane/CloudNativePG → RabbitMQ/Milvus Operator → 平台 API/Agent Platform → 验收应用和访问入口
```

Argo CD 已启用自动同步、`selfHeal` 和 `prune`：

- 本地修改但不提交、不推送，不会影响集群。
- 推送到非 `main` 分支，默认不会影响集群。
- 推送到 `main` 后，Argo CD 会自动应用变化。
- 直接使用 `kubectl` 修改受管资源，可能被 Argo CD 自动改回。
- 从 Git 删除受管资源，可能导致 Argo CD 删除集群中的对应资源。

## 当前生效边界

| 状态 | 目录 | 说明 |
|---|---|---|
| 生效 | `bootstrap/` | Argo CD 根应用入口 |
| 生效 | `clusters/homelab/` | 当前 homelab 的应用清单、版本和部署顺序 |
| 生效 | `infrastructure/` | DNS、证书、存储、密钥同步和访问入口 |
| 生效 | `platform/` | OpenChoreo、Thunder、Harbor、可观测性和平台 API 配置 |
| 生效 | `examples/smoke-app/` | Phase 05 端到端验收应用 |
| 手动 | `scripts/` | 契约验证、在线验收和一次性运维脚本 |
| 文档 | `docs/` | 访问说明、设计和实施记录 |
| 保留模板 | `flux/` | 官方 Flux CD 示例，当前未被 `homelab-root` 引用 |
| 保留模板 | `namespaces/` | 官方 Doclet、ComponentType、Trait 和 Workflow 示例，当前未被 `homelab-root` 引用 |
| 保留模板 | `platform-shared/` | 官方 Argo ClusterWorkflowTemplate 示例，当前未被 `homelab-root` 引用 |

## 目录与文件参考

下面覆盖仓库当前全部受版本控制文件。新增、删除或改变文件用途时，应在同一次提交中更新本节。

### 根目录与 GitHub 配置

| 文件 | 作用 |
|---|---|
| `.github/dco.yml` | 配置 GitHub DCO 检查，要求提交带有开发者签署信息。 |
| `.gitignore` | 忽略编译产物、日志、IDE 配置、压缩包和 OCC 本地索引。它没有授权提交敏感信息。 |
| `LICENSE` | Apache License 2.0 许可证全文。 |
| `README.md` | 本中文维护手册，也是仓库结构、职责边界和操作规则的入口。 |
| `pull_request_template.md` | Pull Request 的目的、实现方法、关联问题、检查项和备注模板。 |

### `bootstrap/`：Argo CD 根入口

| 文件 | 作用 |
|---|---|
| `bootstrap/root-application.yaml` | 创建 `homelab-root` Application，跟踪本仓库 `main` 分支的 `clusters/homelab`，并启用自动同步、自愈和清理。集群首次接入本仓库时需要手动应用一次。 |

### `clusters/homelab/`：集群应用编排

| 文件 | 作用 |
|---|---|
| `clusters/homelab/kustomization.yaml` | 汇总 AppProject 和 32 个子 Application，是 `homelab-root` 的直接渲染入口。文件顺序配合各 Application 的 sync wave 表达部署依赖。 |
| `clusters/homelab/project.yaml` | 定义 `homelab-platform` AppProject，限制允许使用的 Git/Helm/OCI 来源、目标 Namespace 和集群级资源类型。 |

#### `clusters/homelab/applications/`：32 个 Argo CD 子应用

| 文件 | 作用 |
|---|---|
| `00-metallb.yaml` | 安装 MetalLB，并应用内网 IP 地址池与二层广播配置。sync wave `-30`，最先提供 LoadBalancer 能力。 |
| `01-dns.yaml` | 部署 homelab 内部 DNS，并让集群 CoreDNS 转发 `openchoreo.home.arpa` 查询。 |
| `02-ingress-nginx.yaml` | 从官方 Helm 仓库安装 ingress-nginx，读取 `infrastructure/ingress/values.yaml`。 |
| `03-cert-manager.yaml` | 安装 cert-manager 及其 CRD，使用双副本 webhook 和 cainjector。 |
| `04-nfs-csi.yaml` | 安装 NFS CSI Driver，并加载仓库中的 NFS StorageClass。 |
| `05-platform-certificates.yaml` | 应用内部根 CA、ClusterIssuer、平台 Namespace 和各管理平台证书。 |
| `05-argocd-access.yaml` | 为 Argo CD 创建 TLS 证书和 Ingress 浏览器入口。 |
| `06-openbao.yaml` | 安装 OpenBao，读取 `infrastructure/openbao/values.yaml`，并忽略运行时自动写入的 webhook CA Bundle。 |
| `07-external-secrets.yaml` | 安装 External Secrets Operator，并创建 OpenBao SecretStore、连通性探针和 Harbor ExternalSecret。 |
| `08-harbor.yaml` | 安装 Harbor OCI 镜像仓库，读取 `platform/harbor/values.yaml`，同时忽略运行时生成的 Secret 差异。 |
| `09-gateway-api.yaml` | 安装 Kubernetes Gateway API experimental CRD，为 kgateway 和 OpenChoreo 路由提供资源类型。 |
| `10-kgateway-crds.yaml` | 安装 kgateway 自身 CRD。 |
| `11-kgateway.yaml` | 安装 kgateway 控制器，并开启 Gateway API 实验特性。 |
| `12-thunder-secrets.yaml` | 在 Thunder 安装前创建由 OpenBao 驱动的 ExternalSecret。 |
| `13-thunder.yaml` | 安装 Thunder 身份认证服务，合并 Helm values、持久卷和运行时初始化配置。 |
| `14-openchoreo-control-plane.yaml` | 安装 OpenChoreo Control Plane 1.1.2；读取 Control Plane values，并保留已验证的 Backstage 探针和部署策略。 |
| `15-openchoreo-data-plane.yaml` | 安装 OpenChoreo Data Plane 1.1.2，并补充访问 Crossplane 资源所需的 RBAC。 |
| `16-openchoreo-workflow-plane.yaml` | 安装 OpenChoreo Workflow Plane 1.1.2，并补充工作流执行 Namespace、ServiceAccount 和 RBAC。 |
| `17-observability-logs.yaml` | 安装 OpenChoreo 日志栈 `observability-logs-opensearch`，并加载可观测性运行时 Secret。 |
| `18-observability-traces.yaml` | 安装 OpenChoreo Trace 存储栈 `observability-tracing-opensearch`。 |
| `19-observability-metrics.yaml` | 安装 OpenChoreo Prometheus 指标栈。 |
| `20-openchoreo-observability-plane.yaml` | 安装 OpenChoreo Observability Plane 1.1.2，并忽略 Kubernetes 默认补全造成的无意义差异。 |
| `21-crossplane.yaml` | 安装 Crossplane 2.3.3 和双副本 RBAC Manager，为平台资源 API 提供控制器。 |
| `22-cloudnative-pg.yaml` | 安装 CloudNativePG Operator，负责实际创建和维护 PostgreSQL 集群。 |
| `22-rabbitmq-cluster-operator.yaml` | 从 RabbitMQ 官方 Git 发布 `v2.22.2` 安装 Cluster Operator，并固定控制器镜像版本。 |
| `22-milvus-operator.yaml` | 从 Milvus Operator 官方 Helm 仓库安装 `1.3.7`，复用集群现有 cert-manager。 |
| `23-platform-apis.yaml` | 应用 `platform/apis/postgresql`，注册 PostgreSQL XRD、Composition、Function 和 RBAC。 |
| `24-environments.yaml` | 应用 OpenChoreo 的开发、预发布、生产环境、部署流水线、默认项目和 PostgreSQL 资源类型。 |
| `24-agent-platform.yaml` | 应用独立的 Agent Platform Namespace、development Environment、development-only Pipeline 和 Project。 |
| `25-openchoreo-capabilities.yaml` | 注册服务型 ClusterComponentType，并创建 Smoke 应用的 PodMonitor。 |
| `26-smoke-app.yaml` | 部署 Phase 05 Smoke 示例，验证 Component、Workload、API 和 PostgreSQL 资源链路。 |
| `27-ip-access.yaml` | 部署 IP 加端口访问网关，让只使用 Mac 的用户无需依赖内部 DNS 域名访问 Web 管理平台。 |

### `infrastructure/`：集群基础设施

#### `infrastructure/argocd-access/`

| 文件 | 作用 |
|---|---|
| `certificate.yaml` | 为 `argocd.openchoreo.home.arpa` 申请并维护 TLS 证书。 |
| `ingress.yaml` | 将域名流量通过 ingress-nginx 转发到 Argo CD Server，并按 Argo CD 的 HTTPS 后端要求配置。 |
| `kustomization.yaml` | 汇总 Argo CD Certificate 和 Ingress。 |

#### `infrastructure/cert-manager/`

| 文件 | 作用 |
|---|---|
| `certificates.yaml` | 为 OpenBao、Harbor、Thunder、OpenChoreo、Observer 等平台入口创建内部 TLS 证书。 |
| `cluster-issuer.yaml` | 定义 `homelab-root-ca` ClusterIssuer，使用预置的内部根 CA Secret 签发证书。 |
| `kustomization.yaml` | 汇总 Namespace、ClusterIssuer 和平台 Certificate。 |
| `namespaces.yaml` | 预先创建需要在证书签发阶段存在的平台 Namespace。 |

#### `infrastructure/dns/`

| 文件 | 作用 |
|---|---|
| `configmap.yaml` | 保存 CoreDNS 风格的内部域名解析配置，把各管理平台域名指向对应内网地址。 |
| `deployment.yaml` | 部署两副本 homelab DNS，并配置健康检查、资源限制、反亲和与只读安全上下文。 |
| `kubernetes-coredns-custom.yaml` | 为 K3s 自带 CoreDNS 增加 `openchoreo.home.arpa` 条件转发。 |
| `kustomization.yaml` | 汇总内部 DNS ConfigMap、Deployment、Service 和 CoreDNS 扩展配置。 |
| `service.yaml` | 暴露固定 ClusterIP DNS Service，供 CoreDNS 转发查询。 |

#### `infrastructure/external-secrets/`

| 文件 | 作用 |
|---|---|
| `canary.yaml` | 创建 OpenBao 连通性 ExternalSecret，用于验证密钥读取链路。 |
| `cluster-secret-store.yaml` | 定义集群级 OpenBao SecretStore，包括服务地址、挂载路径和 Kubernetes 认证方式。 |
| `harbor.yaml` | 从 OpenBao 读取 Harbor 管理员密码、数据库密码和组件 Secret，生成 Harbor Kubernetes Secret。 |
| `kustomization.yaml` | 汇总 SecretStore、Canary 和 Harbor ExternalSecret。 |

#### `infrastructure/ingress/`

| 文件 | 作用 |
|---|---|
| `kustomization.yaml` | 保留给 ingress-nginx 附加 Kubernetes 资源；当前资源列表为空。 |
| `values.yaml` | 配置 ingress-nginx 的 LoadBalancer、真实客户端 IP、HTTP/HTTPS 端口和控制器参数。 |

#### `infrastructure/ip-access/`

| 文件 | 作用 |
|---|---|
| `certificate.yaml` | 为 `192.168.2.154` IP 入口签发内部 TLS 证书。 |
| `configmap.yaml` | 保存 Nginx 配置：按对外端口分流管理平台，重写域名、OAuth 回调、Thunder Gate 配置和 JSON 响应，并禁用易产生陈旧回调的缓存。 |
| `deployment.yaml` | 部署两副本 IP 访问 Nginx，挂载配置和证书，配置探针、资源限制和安全上下文。 |
| `kustomization.yaml` | 汇总 IP 访问 Namespace、ConfigMap、Certificate、Deployment、Service 和 NetworkPolicy。 |
| `namespace.yaml` | 创建隔离的 `platform-access` Namespace。 |
| `network-policy.yaml` | 限制访问网关的入站和出站网络，只允许必要的管理端口、DNS 和后端服务。 |
| `service.yaml` | 使用 MetalLB `LoadBalancer` 地址 `192.168.2.154` 暴露允许访问的六个 Web 管理平台端口。 |

#### `infrastructure/metallb/`

| 文件 | 作用 |
|---|---|
| `ip-address-pool.yaml` | 定义 homelab 可分配的内网 LoadBalancer 地址池。 |
| `kustomization.yaml` | 汇总 MetalLB 地址池和二层广播。 |
| `l2-advertisement.yaml` | 通过局域网 ARP/NDP 广播 MetalLB 分配的地址。 |

#### `infrastructure/openbao/`

| 文件 | 作用 |
|---|---|
| `kustomization.yaml` | 保留给 OpenBao 附加 Kubernetes 资源；当前资源列表为空。 |
| `values.yaml` | 配置 OpenBao 单节点服务、持久化、Injector、Service、Ingress 和资源限制。 |

#### `infrastructure/storage/`

| 文件 | 作用 |
|---|---|
| `kustomization.yaml` | 汇总两个 NFS StorageClass。 |
| `nfs-storage-class.yaml` | 定义通用 `nfs-shared` StorageClass，供 Harbor、OpenBao、OpenChoreo 和可观测性组件使用。 |
| `thunder-storage-class.yaml` | 定义 Thunder 专用 NFS StorageClass，将身份数据库数据放在独立子目录。 |

### `platform/`：平台产品和平台 API 配置

#### `platform/apis/postgresql/`

其中 `platform/apis/postgresql/examples/` 保存不同环境规格的资源申请示例，不会被该目录的 `kustomization.yaml` 自动部署。

| 文件 | 作用 |
|---|---|
| `composition.yaml` | 把 `XPostgreSQL` 转换为 CloudNativePG Cluster、Service 等实际资源，并映射规格和连接信息。 |
| `definition.yaml` | 定义 `XPostgreSQL` CompositeResourceDefinition，包括开发/生产规格字段、校验规则和连接状态。 |
| `platform/apis/postgresql/examples/development.yaml` | 开发规格的 PostgreSQL 申请示例，使用较少副本和资源。 |
| `platform/apis/postgresql/examples/production.yaml` | 生产规格的 PostgreSQL 申请示例，展示更高可用和资源配置。 |
| `functions.yaml` | 安装 Crossplane `function-patch-and-transform`，供 Composition Pipeline 使用。 |
| `kustomization.yaml` | 汇总 Function、XRD、Composition 和 RBAC；示例申请默认不自动部署。 |
| `rbac.yaml` | 允许 Crossplane 管理 CloudNativePG 组合资源并读取其状态。 |

#### `platform/cloudnative-pg/`

| 文件 | 作用 |
|---|---|
| `kustomization.yaml` | CloudNativePG 附加资源预留入口；Operator 当前直接由 Argo CD Helm Application 安装。 |

#### `platform/crossplane/`

| 文件 | 作用 |
|---|---|
| `kustomization.yaml` | Crossplane Provider 资源的 Kustomize 入口。当前 homelab 根应用未直接引用此目录。 |
| `providers.yaml` | 定义 Crossplane Kubernetes Provider 和 ProviderConfig，用于让 Crossplane 管理本集群资源。 |

#### `platform/harbor/`

| 文件 | 作用 |
|---|---|
| `values.yaml` | 配置 Harbor 域名、TLS、NFS 持久化、数据库、Redis、镜像代理、管理员 Secret 和关闭漏洞扫描等参数。 |

#### `platform/observability/`

| 文件 | 作用 |
|---|---|
| `values-logs.yaml` | 配置日志 OpenSearch 的存储、资源、持久化和内部访问参数。 |
| `values-metrics.yaml` | 配置 Prometheus 指标组件、保留时间、存储和资源限制。 |
| `values-traces.yaml` | 配置 Trace OpenSearch 的持久化与资源参数。 |

#### `platform/openchoreo/`：OpenChoreo 四个 Plane

| 文件 | 作用 |
|---|---|
| `control-plane-values.yaml` | 配置 Control Plane、Backstage、Thunder OIDC、Gateway、域名和 IP 入口允许来源。 |
| `data-plane-values.yaml` | 配置 Data Plane 的 Cluster Agent、网关、镜像仓库和控制面连接信息。 |
| `observability-plane-values.yaml` | 配置 Observer、OpenSearch、Prometheus、Gateway 和 Control Plane 注册参数。 |
| `workflow-plane-values.yaml` | 配置 Workflow Plane、Argo Workflow 执行器、Harbor 和 Control Plane 连接信息。 |

##### `platform/openchoreo/capabilities/`

| 文件 | 作用 |
|---|---|
| `kustomization.yaml` | 汇总服务型 ClusterComponentType 和 Smoke PodMonitor。 |
| `service.yaml` | 定义 OpenChoreo `service` ClusterComponentType，将 Workload 渲染为 Deployment、Service、HTTPRoute 等 Kubernetes 资源。 |
| `smoke-podmonitor.yaml` | 让 Prometheus 采集 Phase 05 Smoke 应用指标。 |

##### `platform/openchoreo/agent-platform/`

| 文件 | 作用 |
|---|---|
| `README.md` | 说明 Agent Platform 控制面资源边界、应用顺序、数据保留和敏感信息规则。 |
| `namespace.yaml` | 创建带 `openchoreo.dev/control-plane=true` 标签的 `agent-platform` Namespace。 |
| `environment-development.yaml` | 创建只绑定默认 ClusterDataPlane 的非生产 `development` Environment。 |
| `deployment-pipeline.yaml` | 创建只有 development 起点且暂无晋级目标的 `development-only` DeploymentPipeline。 |
| `project.yaml` | 创建使用 `development-only` Pipeline 的 `agent-platform` Project。 |
| `resources.yaml` | 申请 development 使用的共享 MinIO、单副本 RabbitMQ 和 standalone Milvus。 |
| `resource-bindings.yaml` | 声明三个资源的 development 发布绑定；初次生成 Release 后把实际名称固定回 Git。 |
| `kustomization.yaml` | 汇总 Agent Platform Namespace、Environment、DeploymentPipeline、Project、Resource 和 ResourceReleaseBinding。 |

##### `platform/openchoreo/data-plane-runtime/`

| 文件 | 作用 |
|---|---|
| `crossplane-rbac.yaml` | 给 OpenChoreo Data Plane 控制器读取和管理 Crossplane PostgreSQL 资源的权限。 |
| `resource-operator-rbac.yaml` | 给 OpenChoreo Data Plane 控制器管理 RabbitMQCluster 和 Milvus 自定义资源的最小权限。 |
| `kustomization.yaml` | 汇总 Crossplane 与 Agent Platform Operator CR 的 Data Plane 额外 RBAC。 |

##### `platform/openchoreo/observability-runtime/`

| 文件 | 作用 |
|---|---|
| `external-secrets.yaml` | 从 OpenBao 读取 OpenSearch 管理员凭据，生成日志和 Trace 组件使用的 Kubernetes Secret。 |
| `kustomization.yaml` | 汇总可观测性 ExternalSecret。 |

##### `platform/openchoreo/resources/`

| 文件 | 作用 |
|---|---|
| `README.md` | 说明 OpenChoreo 1.1.2 环境边界和资源文件的应用顺序。 |
| `cluster-resource-type-postgresql.yaml` | 把 Crossplane `XPostgreSQL` 暴露为 OpenChoreo `postgresql` ClusterResourceType。 |
| `cluster-resource-type-minio.yaml` | 定义由 OpenChoreo 直接渲染的 MinIO、凭据同步和 Bucket 初始化资源合同。 |
| `cluster-resource-type-rabbitmq.yaml` | 把 RabbitMQ Cluster Operator 暴露为单副本 `rabbitmq` ClusterResourceType。 |
| `cluster-resource-type-milvus.yaml` | 把 Milvus Operator 与外部 MinIO 组合为 standalone `milvus` ClusterResourceType。 |
| `deployment-pipeline.yaml` | 定义默认部署流水线及开发、预发布、生产环境的晋级顺序。 |
| `environment-development.yaml` | 定义开发环境并绑定 Data Plane 和 Observability Plane。 |
| `environment-production.yaml` | 定义生产环境并绑定 Data Plane 和 Observability Plane。 |
| `environment-staging.yaml` | 定义预发布环境并绑定 Data Plane 和 Observability Plane。 |
| `kustomization.yaml` | 汇总 PostgreSQL、MinIO、RabbitMQ、Milvus 资源类型，以及三个环境、部署流水线和默认项目。 |
| `project.yaml` | 创建 OpenChoreo 默认 Project，作为组件和资源的逻辑边界。 |

##### `platform/openchoreo/workflow-runtime/`

| 文件 | 作用 |
|---|---|
| `executor-rbac.yaml` | 创建 `workflow-sa` 及相关 Role/RoleBinding，使 Argo Workflow 能构建镜像和操作必要资源。 |
| `kustomization.yaml` | 汇总 `argo-build` Namespace 和工作流执行权限。 |
| `namespace.yaml` | 创建隔离的 `argo-build` Namespace。 |

#### `platform/thunder/`、`platform/thunder-runtime/` 和 `platform/thunder-secrets/`

| 文件 | 作用 |
|---|---|
| `platform/thunder/values.yaml` | Thunder 的完整 Helm 配置，包括数据库、路由、管理员初始化、Backstage OAuth 客户端、回调地址和一次性初始化 Job。 |
| `platform/thunder-runtime/kustomization.yaml` | 汇总 Thunder Chart 之外的持久化资源。 |
| `platform/thunder-runtime/pvc.yaml` | 创建 Thunder 数据库 PVC，使用 Thunder 专用 StorageClass。 |
| `platform/thunder-secrets/external-secrets.yaml` | 从 OpenBao 读取管理员密码、数据库密码和 Backstage Client Secret，生成 Thunder Bootstrap Secret。 |
| `platform/thunder-secrets/kustomization.yaml` | 汇总 Thunder ExternalSecret。 |

### `examples/smoke-app/`：Phase 05 端到端验收

| 文件 | 作用 |
|---|---|
| `examples/smoke-app/api.yaml` | 用 ConfigMap 保存 Smoke HTTP API 契约和验收元数据。 |
| `examples/smoke-app/build.yaml` | 记录 Smoke 镜像构建来源、镜像地址和版本证明。 |
| `examples/smoke-app/component.yaml` | 创建 OpenChoreo `phase05-smoke` Component。 |
| `examples/smoke-app/kustomization.yaml` | 汇总 Smoke Component、Workload、Resource、Binding、API 和构建证明。 |
| `examples/smoke-app/resource-bindings.yaml` | 将 PostgreSQL ResourceRelease 分别绑定到开发、预发布和生产环境。 |
| `examples/smoke-app/resource.yaml` | 创建 OpenChoreo PostgreSQL Resource 申请。 |
| `examples/smoke-app/workload.yaml` | 定义 Smoke 容器镜像、端口、环境变量、资源限制、健康检查和 API Endpoint。 |
| `examples/smoke-app/app/Dockerfile` | 构建精简的 Go Smoke 服务容器镜像。 |
| `examples/smoke-app/app/go.mod` | 定义 Smoke Go 模块和依赖版本。 |
| `examples/smoke-app/app/go.sum` | 锁定 Go 依赖校验和，保证构建可重复。 |
| `examples/smoke-app/app/main.go` | 实现健康检查、就绪检查、指标和 PostgreSQL 连通性测试接口。 |
| `examples/smoke-app/app/main_test.go` | 测试 Smoke 服务路由、健康状态、响应内容和数据库错误处理。 |

### `scripts/`：运维和验证

#### `scripts/operations/`

| 文件 | 作用 |
|---|---|
| `register-data-plane.sh` | 从 Control Plane 复制集群网关 CA，等待 Data Plane Cluster Agent 就绪，再创建或更新 `ClusterDataPlane/default`。 |
| `register-observability-plane.sh` | 从 Control Plane 复制集群网关 CA，等待 Observability Plane Cluster Agent 就绪，再创建或更新 `ClusterObservabilityPlane/default`。 |
| `register-workflow-plane.sh` | 从 Control Plane 复制集群网关 CA，等待 Workflow Plane Cluster Agent 就绪，再创建或更新 `ClusterWorkflowPlane/default`。 |
| `tune-backstage-probes.sh` | 对已部署的 Backstage 应用经过验证的启动、存活和就绪探针参数；用于 Chart 探针过于激进时的运维调整。 |

#### `scripts/verify/`

| 文件 | 作用 |
|---|---|
| `agent-platform-control-plane.sh` | 检查 Agent Platform Namespace、Environment、DeploymentPipeline、Project 和 Argo CD Application 契约。 |
| `agent-platform-foundation.sh` | 聚合 Agent Platform Operator、RBAC、控制面、渲染和凭据特征检查。 |
| `agent-platform-operators.sh` | 检查 RabbitMQ/Milvus Operator 的官方来源、固定版本和 App-of-Apps 注册。 |
| `agent-platform-rbac.sh` | 检查 OpenChoreo Data Plane 的 RabbitMQ/Milvus CR 最小权限，并执行 Server-Side Dry Run。 |
| `agent-platform-resources.sh` | 检查 MinIO、RabbitMQ、Milvus ResourceType、Resource、Binding 合同，并执行 Server-Side Dry Run。 |
| `control-plane.sh` | 渲染并检查 Control Plane Helm 配置、Secret 引用、OIDC 和 IP 来源白名单契约。 |
| `crossplane-install.sh` | 检查 Crossplane Helm 安装清单、版本、双副本和 Argo CD Application 配置。 |
| `crossplane.sh` | 检查 PostgreSQL XRD、Composition、Function、RBAC 和示例规格，并通过 Kubernetes Server Dry Run 验证渲染结果。 |
| `data-plane.sh` | 检查 Data Plane Chart、注册信息、RBAC、Pod 和 Argo CD 状态。 |
| `end-to-end.sh` | 串联关键验证脚本，形成 OpenChoreo 平台端到端验收入口。 |
| `entrypoints.sh` | 渲染并检查 Argo CD 域名入口的 Application、Ingress、TLS Secret 和后端 Service 契约。 |
| `ip-access-live.sh` | 从网络侧实际请求 IP+端口入口，检查 TLS、HTTP 状态、跳转和后端可达性。 |
| `ip-access.sh` | 静态检查 IP 访问 Nginx、NodePort、证书、地址重写、缓存和 NetworkPolicy 契约。 |
| `observability-plane.sh` | 渲染并检查 Observability Plane、日志、Trace、Metrics、Secret、存储、差异忽略规则和运行时资源契约。 |
| `observability.sh` | 静态检查 Smoke 应用是否暴露指标和 Trace，以及 PodMonitor 是否选择正确的 Pod。 |
| `openbao.sh` | 检查 OpenBao Argo CD Application 是否只忽略运行时注入的 webhook CA Bundle，并在同步时尊重该差异规则。 |
| `openchoreo-environments.sh` | 检查三个 Environment、DeploymentPipeline、Project 和 PostgreSQL ClusterResourceType。 |
| `openchoreo.sh` | 检查 Phase 05 Smoke 所需的 ClusterComponentType、Component、Workload、Resource 和三环境 Binding，并执行 Kustomize 与 Server Dry Run。 |
| `policies.sh` | 检查安全上下文、网络策略、RBAC 和禁止明文 Secret 等仓库策略。 |
| `render.sh` | 使用 Kustomize 渲染 `clusters/homelab`，再用 Kubernetes Client Dry Run 捕获 YAML 和资源引用错误。 |
| `secrets.sh` | 检查 OpenBao、External Secrets、SecretStore 和各平台 ExternalSecret 链路。 |
| `thunder.sh` | 检查 Thunder Chart、持久化、Bootstrap Secret、OAuth 客户端和回调地址更新逻辑。 |
| `workflow-plane.sh` | 检查 Workflow Plane Chart、执行 Namespace、ServiceAccount、RBAC 和 Plane 注册状态。 |

### `docs/`：设计、操作和历史记录

| 文件 | 作用 |
|---|---|
| `docs/access/ip-port-web-access.md` | IP+端口管理平台访问手册，包含地址、前提、自动验收、排障、回滚和限制。 |
| `docs/superpowers/plans/2026-07-13-ip-port-web-access.md` | IP 访问入口的分任务实施计划和验收步骤，作为变更历史保留。 |
| `docs/superpowers/plans/2026-07-15-agent-platform-managed-resources.md` | Agent Platform 开发环境 MinIO、RabbitMQ、Milvus 的测试先行、分阶段发布和集群验收计划。 |
| `docs/superpowers/plans/2026-07-15-agent-platform-postgresql-redis.md` | Agent Platform development 环境 PostgreSQL、Redis 的凭据、Resource、Release 固定和在线验收计划。 |
| `docs/superpowers/specs/2026-07-13-ip-port-web-access-design.md` | IP 访问入口的目标、架构、端口、路由、安全边界和回滚设计。 |
| `docs/superpowers/specs/2026-07-15-agent-platform-managed-resources-design.md` | Agent Platform 开发环境 MinIO、RabbitMQ、Milvus 的 OpenChoreo 资源、凭据、发布顺序和验收设计。 |
| `docs/superpowers/specs/2026-07-15-agent-platform-postgresql-redis-design.md` | Agent Platform development 环境 PostgreSQL、Redis 的单实例资源、凭据边界、发布与验收设计。 |

### `flux/`：官方 Flux CD 保留示例

当前 homelab 使用 Argo CD App-of-Apps，这个目录没有被 `homelab-root` 引用。保留它是为了参考官方 Flux 工作流或将来迁移，不要误认为它正在管理当前集群。

| 文件 | 作用 |
|---|---|
| `flux/README.md` | 官方 Flux 教程，说明安装 Flux、准备 Git Secret、部署 Doclet 和环境晋级。 |
| `flux/gitrepository.yaml` | 定义 Flux GitRepository，指向本 GitOps 仓库。 |
| `flux/namespaces-kustomization.yaml` | 让 Flux 同步 `namespaces/` 的 Namespace 入口。 |
| `flux/oc-demo-platform-kustomization.yaml` | 同步默认 Namespace 下的 Environment、ComponentType、Trait 和 Workflow，并依赖 Namespace 同步完成。 |
| `flux/oc-demo-projects-kustomization.yaml` | 同步 Doclet Project、Component、Workload、Release 和 ReleaseBinding。 |
| `flux/platform-shared-kustomization.yaml` | 同步集群级 Argo ClusterWorkflowTemplate。 |

### `platform-shared/`：官方集群工作流模板

当前没有被 `homelab-root` 引用，主要作为 OpenChoreo GitOps 发布流程模板保留。

| 文件 | 作用 |
|---|---|
| `platform-shared/cluster-workflow-templates/argo/README.md` | 说明四类 ClusterWorkflowTemplate、与 OpenChoreo Workflow 的关系及使用的构建镜像。 |
| `platform-shared/cluster-workflow-templates/argo/bulk-gitops-release-template.yaml` | 不重新构建镜像，批量为现有 ComponentRelease 生成目标环境 ReleaseBinding 和 Git PR。 |
| `platform-shared/cluster-workflow-templates/argo/docker-with-gitops-release-template.yaml` | 克隆带 Dockerfile 的源码、构建并推送镜像、生成 OpenChoreo Release 清单并创建 GitOps PR。 |
| `platform-shared/cluster-workflow-templates/argo/google-cloud-buildpacks-gitops-release-template.yaml` | 使用 Google Cloud Buildpacks 自动识别语言、构建镜像、生成 Release 并创建 GitOps PR。 |
| `platform-shared/cluster-workflow-templates/argo/react-gitops-release-template.yaml` | 构建 React/SPA 静态站点镜像、生成 Release 清单并创建 GitOps PR。 |

### `namespaces/`：官方 OpenChoreo Doclet 保留示例

当前没有被 `homelab-root` 引用。这里展示平台团队如何定义能力，以及开发团队如何声明项目和组件。

#### Namespace 和平台基础资源

| 文件 | 作用 |
|---|---|
| `namespaces/kustomization.yaml` | 官方示例的 Namespace 汇总入口。 |
| `namespaces/default/namespace.yaml` | 声明默认 Namespace，并添加 OpenChoreo 所需标签。 |
| `namespaces/default/platform/infra/deployment-pipelines/standard.yaml` | 定义 development → staging → production 的标准部署流水线。 |
| `namespaces/default/platform/infra/environments/development.yaml` | 定义官方示例开发环境。 |
| `namespaces/default/platform/infra/environments/production.yaml` | 定义官方示例生产环境。 |
| `namespaces/default/platform/infra/environments/staging.yaml` | 定义官方示例预发布环境。 |

#### ComponentType 和 Trait

| 文件 | 作用 |
|---|---|
| `namespaces/default/platform/component-types/database.yaml` | 定义数据库 ComponentType 的参数、Kubernetes 资源渲染和状态映射。 |
| `namespaces/default/platform/component-types/message-broker.yaml` | 定义消息代理 ComponentType，例如 NATS 的服务、工作负载和配置渲染。 |
| `namespaces/default/platform/component-types/service.yaml` | 定义后端服务 ComponentType，渲染 Deployment、Service、HTTPRoute 和可观测性配置。 |
| `namespaces/default/platform/component-types/webapp.yaml` | 定义 Web 应用 ComponentType，渲染前端 Deployment、Service 和 HTTPRoute。 |
| `namespaces/default/platform/traits/api-management.yaml` | 定义 API 管理 Trait，把 API 配置附加到组件渲染结果。 |
| `namespaces/default/platform/traits/observability-alert-rule.yaml` | 定义可观测性告警规则 Trait。 |
| `namespaces/default/platform/traits/persistent-volume.yaml` | 定义持久卷 Trait，为组件附加 PVC 和 VolumeMount。 |

#### OpenChoreo Workflow

| 文件 | 作用 |
|---|---|
| `namespaces/default/platform/workflows/README.md` | 说明四种 GitOps Workflow 的参数、运行方式和使用场景。 |
| `namespaces/default/platform/workflows/bulk-gitops-release.yaml` | 定义批量晋级已有 Release 的 OpenChoreo Workflow。 |
| `namespaces/default/platform/workflows/docker-with-gitops-release.yaml` | 定义 Dockerfile 构建与 GitOps Release Workflow，并引用对应 ClusterWorkflowTemplate。 |
| `namespaces/default/platform/workflows/google-cloud-buildpacks-gitops-release.yaml` | 定义 Buildpacks 构建与 GitOps Release Workflow。 |
| `namespaces/default/platform/workflows/react-gitops-release.yaml` | 定义 React 构建与 GitOps Release Workflow。 |

#### Doclet Project 和业务组件

| 文件 | 作用 |
|---|---|
| `namespaces/default/projects/doclet/project.yaml` | 创建官方 Doclet 示例 Project。 |
| `namespaces/default/projects/doclet/components/collab-svc/component.yaml` | 定义 Doclet 协作服务 Component 及构建参数。 |
| `namespaces/default/projects/doclet/components/collab-svc/workload.yaml` | 定义协作服务容器、端口、环境变量和依赖。 |
| `namespaces/default/projects/doclet/components/document-svc/component.yaml` | 定义 Doclet 文档服务 Component。 |
| `namespaces/default/projects/doclet/components/document-svc/workload.yaml` | 定义文档服务容器、API、环境变量和数据库/消息代理依赖。 |
| `namespaces/default/projects/doclet/components/frontend/component.yaml` | 定义 Doclet 前端 Component。 |
| `namespaces/default/projects/doclet/components/frontend/workload.yaml` | 定义前端容器、Web Endpoint 和后端服务地址。 |
| `namespaces/default/projects/doclet/components/nats/component.yaml` | 定义 NATS 消息代理 Component。 |
| `namespaces/default/projects/doclet/components/nats/workload.yaml` | 定义 NATS 版本、存储和代理参数。 |
| `namespaces/default/projects/doclet/components/nats/releases/nats-20260223-1.yaml` | 保存 NATS Component 与 Workload 的不可变发布快照。 |
| `namespaces/default/projects/doclet/components/nats/release-bindings/nats-development.yaml` | 将 NATS Release 部署到 development。 |
| `namespaces/default/projects/doclet/components/nats/release-bindings/nats-staging.yaml` | 将同一 NATS Release 部署到 staging。 |
| `namespaces/default/projects/doclet/components/postgres/component.yaml` | 定义 PostgreSQL 数据库 Component。 |
| `namespaces/default/projects/doclet/components/postgres/workload.yaml` | 定义 PostgreSQL 版本、存储和数据库参数。 |
| `namespaces/default/projects/doclet/components/postgres/releases/postgres-20260223-1.yaml` | 保存 PostgreSQL Component 与 Workload 的不可变发布快照。 |
| `namespaces/default/projects/doclet/components/postgres/release-bindings/postgres-development.yaml` | 将 PostgreSQL Release 部署到 development。 |
| `namespaces/default/projects/doclet/components/postgres/release-bindings/postgres-staging.yaml` | 将同一 PostgreSQL Release 部署到 staging。 |

## 常用维护操作

### 修改平台组件配置

1. 在 `clusters/homelab/applications/` 确认 Application 使用的 Chart 版本和 values 路径。
2. 修改对应 `infrastructure/` 或 `platform/` 文件。
3. 运行相关 `scripts/verify/*.sh`。
4. 检查差异后提交并推送。
5. 在 Argo CD 中确认应用恢复为 `Synced / Healthy`。

### 新增平台组件

1. 在 `infrastructure/<组件>/` 或 `platform/<组件>/` 添加 values/Kustomize 资源。
2. 在 `clusters/homelab/applications/` 添加 Argo CD Application。
3. 在 `clusters/homelab/kustomization.yaml` 注册该 Application。
4. 根据依赖设置 sync wave。
5. 增加对应验证脚本，并更新本 README 的生效边界与逐文件说明。

### 验证仓库

根据变更范围运行对应脚本。涉及全平台时可从以下命令开始：

```bash
bash scripts/verify/render.sh
bash scripts/verify/policies.sh
bash scripts/verify/secrets.sh
bash scripts/verify/openchoreo.sh
bash scripts/verify/end-to-end.sh
git diff --check
```

需要访问集群的脚本通过 `KUBECONFIG` 环境变量读取凭据；不要把 Kubeconfig 复制进本仓库。

## 敏感信息边界

本仓库只保存 ExternalSecret、SecretStore 和 Secret 名称引用，不保存真实 Secret 值。以下内容必须留在 `openchoreo-infra/.private/`、OpenBao 或其他受控位置：

- root 密码和平台管理员密码
- SSH 私钥
- Kubeconfig
- Terraform State
- GitHub Token、Harbor Token、Thunder Client Secret
- OpenBao 解封密钥和 Root Token

即使 `.gitignore` 没有匹配某个敏感文件，也不代表可以提交。提交前至少运行：

```bash
git status --short
git diff --cached
```

## 仓库之间的职责

```text
openchoreo-infra
  └─ Proxmox、VM、磁盘、Cloud-Init、Ansible、K3s、私密配置
       └─ openchoreo-gitops
            └─ K3s 内的平台软件、配置、资源和持续同步
                 └─ openchoreo
                      └─ OpenChoreo 产品源代码
```

## README 维护规则

- 新增文件时，在本 README 的对应目录表格中增加说明。
- 删除或改名文件时，同步删除或修正旧说明。
- 改变目录是否由 `homelab-root` 管理时，同步更新“当前生效边界”。
- 改变 Chart 版本、访问地址、Secret 来源或部署顺序时，同时更新相关说明和验证脚本。
- README 描述以当前 `main` 分支实际配置为准，不以旧计划或官方示例为准。
