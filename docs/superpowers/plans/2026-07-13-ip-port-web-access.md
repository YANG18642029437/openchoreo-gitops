# IP 加端口 Web 管理入口实施计划

> **执行要求：** 按任务逐项执行并使用复选框跟踪；本次使用 `superpowers:executing-plans` 在当前会话内实施，不启用子代理，不使用 `.worktrees`。

**目标：** 建设 `192.168.2.154:31001-31006` 私有 HTTPS 网关，使当前 Mac 能通过 IP 加端口访问六个已批准的 Web 管理平台，同时不暴露内部平台服务。

**架构：** 两副本无特权 Nginx 使用内部 CA 的 IP 证书终止 TLS，每个平台使用一个独立监听端口。MetalLB LoadBalancer Service 发布固定 IP，并把来源限制为当前 Mac；每个监听器使用规范 Host 请求头转发到既有 Ingress 或 Gateway API 路由。

**技术栈：** Kubernetes、Kustomize、Argo CD、MetalLB、cert-manager、Cilium NetworkPolicy、无特权 Nginx、Bash 验证脚本、Harbor OCI Registry

---

### 任务 1：地址预检与契约测试

**文件：**
- 新建：`scripts/verify/ip-access.sh`

- [x] **步骤 1：编写预期失败的静态契约**

验证器要求以下资源存在：

```text
infrastructure/ip-access/namespace.yaml
infrastructure/ip-access/configmap.yaml
infrastructure/ip-access/certificate.yaml
infrastructure/ip-access/deployment.yaml
infrastructure/ip-access/service.yaml
infrastructure/ip-access/network-policy.yaml
infrastructure/ip-access/kustomization.yaml
clusters/homelab/applications/27-ip-access.yaml
```

检查固定 IP、六个端口、`192.168.31.97/32` 来源限制、双副本、反亲和、IP SAN
证书、Harbor digest 镜像，并禁止 NodePort、通配 CORS 和通配重定向。

- [x] **步骤 2：运行测试并确认 RED**

```bash
./scripts/verify/ip-access.sh
```

预期：非零退出，并报告 `missing IP access file`。实际结果符合预期。

- [x] **步骤 3：只读检查地址占用**

```bash
ping -c 2 -W 1000 192.168.2.154
arp -an | grep '192.168.2.154'
kubectl -n metallb-system get ipaddresspool homelab -o yaml
kubectl get service -A -o wide | grep '192.168.2.154'
```

预期：`.154` 没有 Ping、ARP 或 Service 所有者，并且位于 MetalLB 地址池。实际检查通过。

- [x] **步骤 4：提交 RED 契约**

```bash
git add scripts/verify/ip-access.sh
git commit -m "test: define IP access gateway contract"
```

### 任务 2：镜像固定版本代理

**后续修改文件：**
- `infrastructure/ip-access/deployment.yaml`

- [x] **步骤 1：拉取固定版本无特权镜像**

```bash
docker pull nginxinc/nginx-unprivileged:1.29.3-alpine
```

预期：拉取成功。上游 digest 为
`sha256:5aea7cc516b419e3526f47dd1531be31a56a046cfe44754d94f9383e13e2ee99`。

- [ ] **步骤 2：镜像到 Harbor**

从 `../openchoreo-infra/.private/openbao/harbor.env` 加载凭据但不输出，使用
`--password-stdin` 登录，然后执行：

```bash
skopeo copy --override-os linux --override-arch amd64 \
  docker://docker.io/nginxinc/nginx-unprivileged:1.29.3-alpine \
  docker://harbor.openchoreo.home.arpa/openchoreo/ip-access-nginx:1.29.3-alpine-amd64
```

实际 Harbor digest 为 `sha256:f7d0d0f2ebc0486dc110278672b9073f7fd641e58376b112b0c8865cf36d2e36`。
Deployment 只能使用 Harbor 仓库加该 digest，不能只使用 tag。

### 任务 3：实现访问网关

**文件：**
- 新建：`infrastructure/ip-access/namespace.yaml`
- 新建：`infrastructure/ip-access/configmap.yaml`
- 新建：`infrastructure/ip-access/certificate.yaml`
- 新建：`infrastructure/ip-access/deployment.yaml`
- 新建：`infrastructure/ip-access/service.yaml`
- 新建：`infrastructure/ip-access/network-policy.yaml`
- 新建：`infrastructure/ip-access/kustomization.yaml`

- [ ] **步骤 1：增加命名空间与 IP 证书**

创建 `platform-access` 命名空间和 `ip-access-tls` Certificate，使用 ClusterIssuer
`homelab-root-ca`、Secret `ip-access-tls`，证书包含：

```yaml
ipAddresses:
  - 192.168.2.154
```

- [ ] **步骤 2：增加六个 TLS 代理监听器**

ConfigMap 定义 `8441-8446` 监听器，加载 `/etc/nginx/tls/tls.crt` 和 `tls.key`，支持
HTTP/1.1、WebSocket Upgrade、长连接，并按下表转发：

```text
8441 -> argocd-server.argocd.svc:443                    Host argocd.openchoreo.home.arpa
8442 -> ingress-nginx-controller.ingress-nginx.svc:443  Host harbor.openchoreo.home.arpa
8443 -> ingress-nginx-controller.ingress-nginx.svc:443  Host openbao.openchoreo.home.arpa
8444 -> gateway-default.openchoreo-control-plane.svc:80 Host openchoreo.home.arpa
8445 -> gateway-default.openchoreo-observability-plane.svc:80 Host observer.openchoreo.home.arpa
8446 -> gateway-default.openchoreo-control-plane.svc:80 Host thunder.openchoreo.home.arpa
```

为每个平台增加明确的 `proxy_redirect`，将规范域名跳转改写成对应 IP 加端口。仅允许对
OpenChoreo 的 Backstage 运行时 app-config JSON 做定点 URL 替换，禁止修改压缩 JS bundle。

- [ ] **步骤 3：增加双副本 Deployment**

使用任务 2 得到的 Harbor digest，并配置：

- `runAsNonRoot`、只读根文件系统、删除全部 capabilities、`seccomp: RuntimeDefault`。
- requests 为 `25m/32Mi`，limits 为 `250m/128Mi`。
- 按 hostname 强制 Pod 反亲和。
- 在 8441 配置 TCP 存活和就绪探针。
- ConfigMap 与 TLS Secret 只读挂载。
- 为无特权 Nginx 的 `/tmp`、缓存和 PID 目录提供内存型 `emptyDir`。

- [ ] **步骤 4：增加固定 LoadBalancer Service**

```yaml
type: LoadBalancer
metallb.io/loadBalancerIPs: 192.168.2.154
loadBalancerSourceRanges:
  - 192.168.31.97/32
allocateLoadBalancerNodePorts: false
```

将 `31001-31006` 映射到 `8441-8446`，禁止显式 `nodePort`。

- [ ] **步骤 5：增加最小权限 NetworkPolicy**

默认拒绝入站和出站；只允许 8441-8446 入站、到 kube-dns 的 TCP/UDP 53，以及到
`argocd`、`ingress-nginx`、`openchoreo-control-plane`、
`openchoreo-observability-plane` 命名空间的 TCP 80/443/8200 出站。

- [ ] **步骤 6：渲染并确认契约 GREEN**

```bash
kubectl kustomize infrastructure/ip-access >/tmp/ip-access.yaml
kubectl apply --dry-run=client -f /tmp/ip-access.yaml
kubectl apply --dry-run=server -f infrastructure/ip-access/namespace.yaml
./scripts/verify/ip-access.sh
```

预期：完整 client dry-run、Namespace 服务端 dry-run 和静态契约全部 PASS；Namespace
实际存在后，验证器自动对完整资源执行服务端 dry-run。

- [ ] **步骤 7：提交网关资源**

```bash
git add infrastructure/ip-access scripts/verify/ip-access.sh
git commit -m "feat: add private IP Web access gateway"
```

### 任务 4：通过 Argo CD 部署

**文件：**
- 新建：`clusters/homelab/applications/27-ip-access.yaml`
- 修改：`clusters/homelab/kustomization.yaml`

- [ ] **步骤 1：增加子 Application**

使用 project `homelab-platform`、目标命名空间 `platform-access`、路径
`infrastructure/ip-access`、sync wave `80`、自动 prune/self-heal，并在实施阶段跟踪
`codex/ip-port-web-access`。

- [ ] **步骤 2：注册到根 Kustomization**

追加 `applications/27-ip-access.yaml`，渲染根目录并运行：

```bash
./scripts/verify/render.sh
./scripts/verify/secrets.sh
./scripts/verify/ip-access.sh
```

- [ ] **步骤 3：提交并推送实施分支**

```bash
git add clusters/homelab
git commit -m "feat: deploy IP access gateway with Argo CD"
git push -u origin codex/ip-port-web-access
```

- [ ] **步骤 4：部署并等待健康**

仅为引导分支跟踪而直接应用 Application，然后等待 `ip-access` Application
`Synced/Healthy`、Certificate Ready、Deployment 2/2，以及 LoadBalancer 获得 `.154`。

- [ ] **步骤 5：确认集群观察到的 Mac 来源地址**

从 Mac 请求一个入口。如果 `/32` 限制拒绝访问，只捕获宣布节点上连接的来源地址元数据，
把规则改成实际观察到的单个 `/32` 后重试，禁止扩大到整个网段。

### 任务 5：验证六个 Web 平台

**文件：**
- 新建：`scripts/verify/ip-access-live.sh`
- 新建：`docs/access/ip-port-web-access.md`

- [ ] **步骤 1：增加自动化在线探测**

不使用 `-k` 请求六个 IP-port URL，要求内部 CA 证书有效、响应为已记录的 2xx/3xx，
禁止跳回规范域名，验证证书 IP SAN，并确认内部 ClusterIP 服务没有新增外部入口。

- [ ] **步骤 2：验证浏览器行为**

使用已有登录状态的 Chrome，逐一检查页面加载、登录、导航、API、重定向循环、Cookie 和
WebSocket。OpenChoreo 额外验证 Thunder 登录回调、项目页和组件页。

- [ ] **步骤 3：验证现有域名入口无回归**

对六个规范域名运行相同的基础操作，确保原入口继续可用。

- [ ] **步骤 4：验证网关单 Pod 故障**

不删除任何平台资源。仅滚动重启一个网关 Pod，确认六个入口持续可用并恢复到 2/2。

- [ ] **步骤 5：记录入口并提交**

文档记录六个 URL、来源限制、CA 要求、排障和回滚，然后提交：

```bash
git add scripts/verify/ip-access-live.sh docs/access/ip-port-web-access.md
git commit -m "test: verify IP port Web access"
```

### 任务 6：合并并切回 main

**文件：**
- 修改：`clusters/homelab/applications/27-ip-access.yaml`

- [ ] **步骤 1：在实施分支执行最终验证**

```bash
./scripts/verify/render.sh
./scripts/verify/secrets.sh
./scripts/verify/policies.sh
./scripts/verify/ip-access.sh
./scripts/verify/ip-access-live.sh
```

只有子 Application 临时跟踪实施分支时，policy 测试允许出现预期失败；其他检查必须通过。

- [ ] **步骤 2：合并到 main 并推送**

不使用 worktree。先合并并推送 `main`，再把子 Application 改为跟踪 `main`，重新运行
全部五项验证并确保零失败，提交后再次推送。

- [ ] **步骤 3：确认 Argo 收敛**

把运行中的子 Application 切回 `main`，等待根应用和子应用 `Synced/Healthy`，重新运行
六个在线探测，并确认 Git 工作区干净。
