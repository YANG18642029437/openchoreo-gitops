# 内网 IP 加端口 Web 管理入口设计

日期：2026-07-13  
状态：待用户复核  
实施分支：`codex/ip-port-web-access`

## 目标

在不依赖本地 DNS、`hosts` 文件或代理软件规则的情况下，从当前 Mac 通过一个固定内网
IP 和六个固定 HTTPS 端口访问 Web 管理平台。现有域名入口继续保留，内部数据库、指标、
日志和控制接口不对内网新增暴露。

## 非目标

- 不开放 PostgreSQL、Prometheus、OpenSearch、OTLP、Kubernetes API 或 OpenChoreo
  内部 API 的独立入口。
- 不改变现有域名入口、证书、应用 Service 类型或业务数据。
- 不把服务暴露到公网，不为其他内网终端提供默认访问权限。
- 不使用 NodePort 直接绕过现有 Ingress、Gateway API 和认证路径。

## 固定访问地址

| 平台 | 地址 |
|---|---|
| Argo CD | `https://192.168.2.154:31001` |
| Harbor | `https://192.168.2.154:31002` |
| OpenBao | `https://192.168.2.154:31003` |
| OpenChoreo | `https://192.168.2.154:31004` |
| Observer | `https://192.168.2.154:31005` |
| Thunder | `https://192.168.2.154:31006` |

`192.168.2.154` 当前不在已分配的五个 MetalLB 地址中；实施前仍必须通过 ARP、ICMP、
MetalLB Service 状态和现有设备清单进行冲突检查，任何冲突都停止实施。

## 架构

新增 `platform-access` 命名空间和一个专用 Web access gateway：

- 两个反向代理 Pod，跨节点调度，使用固定版本和 digest 的镜像；镜像先镜像到本地 Harbor。
- 一个 `LoadBalancer` Service，固定申请 `192.168.2.154`，只发布六个 HTTPS 端口。
- 一个由现有内部 CA 签发的证书，SAN 包含 IP `192.168.2.154`，六个端口共用。
- 一个 ConfigMap 保存无敏感信息的路由、Host、重定向和 WebSocket 设置。
- 一个 NetworkPolicy 只允许 DNS、Kubernetes 健康检查以及到既有 Web 上游的连接。
- Service 使用来源地址限制。Mac 通过 OpenVPN 地址 `10.8.0.10` 访问服务器网段，OpenVPN
  网关将来源 SNAT 为集群实际观察到的 `192.168.1.108`，因此只允许 `192.168.1.108/32`。

访问数据流：

```text
Mac
  -> 192.168.2.154:31001-31006 (HTTPS, IP SAN certificate)
  -> platform-access gateway
  -> existing Ingress/Gateway or Web service
  -> existing authentication and application
```

## 路由原则

网关为每个监听端口设置原有域名 Host，从而复用已经验证的路由：

- Argo CD、Harbor、OpenBao 进入现有 ingress-nginx HTTPS 入口。
- OpenChoreo 和 Thunder 进入 Control Plane `gateway-default`，分别使用原有 Host。
- Observer 进入 Observability Plane `gateway-default`，使用原有 Host。

代理必须支持 HTTP/1.1、WebSocket Upgrade、长连接、流式响应和 Harbor 大文件请求。上游
`Location` 中的已知域名要改写为对应 `IP:端口`；Cookie 不得被改写为其他平台端口。

## 应用兼容性

域名继续作为平台规范地址，IP 入口属于仅供当前 Mac 使用的兼容入口：

- Argo CD：验证登录、应用列表、资源详情和实时状态流。
- Harbor：验证登录、项目列表、artifact 页面和退出；CLI registry 不纳入 IP 入口范围。
- OpenBao：验证 UI 加载、token 登录、secret 列表读取和退出。
- OpenChoreo：验证登录跳转、回调、首页、项目和组件页面。只对运行时配置响应中的已知
  `frontend.baseUrl`、`backend.baseUrl` 和认证回调地址做定点替换；禁止修改压缩 JS bundle。
- Observer：验证页面、API 请求和实时数据加载。
- Thunder：验证登录页和管理页面；OpenChoreo 使用的既有域名回调继续有效，同时增加
  `https://192.168.2.154:31004` 对应的精确回调地址，不允许通配回调。

如果某个平台不能在保留域名入口的同时可靠支持 IP origin，该端口必须保持关闭并记录原因，
不能以关闭 CORS、通配 redirect URI 或全局禁用 TLS 的方式绕过。

## 安全边界

- 对外只接受 HTTPS；不发布 HTTP 端口，不允许明文传输登录凭据。
- 证书包含 IP SAN，使用现有内部 CA；Mac 必须信任该 CA。
- LoadBalancer 来源限制只允许实际观察到的 Mac 源地址。
- 不在 ConfigMap、日志或 Git 中保存账号、密码、token、私钥或 kubeconfig。
- 代理访问日志不记录 Authorization、Cookie、请求正文或查询参数。
- 原有平台 RBAC、登录和会话机制保持不变，网关不提供认证旁路。

## GitOps 组织

新增独立目录 `infrastructure/ip-access`，包含 namespace、Deployment、Service、Certificate、
ConfigMap、NetworkPolicy 和验证用资源；新增一个 Argo CD Application 管理该目录。根应用
保持 `main`，实施阶段子应用临时跟踪实施分支，验收后合并并切回 `main`。

## 验收

实施完成必须满足：

1. `192.168.2.154` 由 MetalLB 唯一分配，两个网关 Pod 分布在不同节点且 Ready。
2. 当前 Mac 能使用六个指定 URL；其他来源地址被拒绝。
3. 六个平台逐项完成页面、登录、API、跳转、Cookie 和 WebSocket 检查。
4. 现有六个域名入口仍可使用，没有证书、CORS、OAuth 或路由回归。
5. PostgreSQL、Prometheus、OpenSearch 和 Kubernetes 内部 Service 仍为 ClusterIP。
6. 停止承载其中一个网关 Pod 的节点后，六个入口继续可用；节点恢复后重新达到 2/2。
7. 静态检查确认镜像固定、没有明文 Secret、没有 NodePort、没有通配 CORS 或 OAuth 回调。

## 回滚

回滚只删除 `platform-access` Application 所管理的网关资源并释放 `192.168.2.154`；不删除
任何原平台 Service、Ingress、HTTPRoute、证书、账号或业务数据。回滚后原有域名入口保持
不变。
