# IP 加端口访问 Web 平台

这组入口通过 MetalLB 固定地址 `192.168.2.154` 提供 HTTPS，只允许当前 Mac 的
OpenVPN 地址 `10.8.0.10/32` 访问。原有域名入口继续保留。

| 平台 | 访问地址 | 说明 |
| --- | --- | --- |
| Argo CD | `https://192.168.2.154:31001/` | GitOps 管理界面 |
| Harbor | `https://192.168.2.154:31002/` | 镜像仓库管理界面 |
| OpenBao | `https://192.168.2.154:31003/ui/` | 密钥管理界面 |
| OpenChoreo | `https://192.168.2.154:31004/` | 开发者门户 |
| Observer | `https://192.168.2.154:31005/health` | Observer 是平台 API，不是独立管理界面；日常观测从 OpenChoreo 门户进入 |
| Thunder | `https://192.168.2.154:31006/console/` | 身份服务管理控制台；`/gate/` 是登录界面 |

## 使用前提

1. Mac 必须信任 `openchoreo-infra/.private/pki/root-ca.crt` 对应的内部根 CA。
2. 保持 OpenVPN 连接；`192.168.2.0/24` 通过 `utun7` 和 OpenVPN 对端 `10.8.0.9` 访问。
3. OpenVPN 分配给 Mac 的地址发生变化后，必须把 `service.yaml` 中的来源限制改成新的单个 `/32`，禁止为了方便开放整个网段。

Shadowrocket 使用的是 `utun4`，OpenVPN 使用的是 `utun7`。访问服务器网段走 `utun7`
是正确行为，不需要关闭 Shadowrocket；如果全部端口超时，应先检查 OpenVPN 地址是否仍在来源白名单内。

## 自动验收

```bash
export KUBECONFIG=../openchoreo-infra/.private/kubeconfigs/homelab-admin-direct.yaml
./scripts/verify/ip-access-live.sh
```

脚本不使用 `curl -k`：它会验证内部 CA、证书的 `192.168.2.154` IP SAN、六条 HTTPS
链路、重定向目标、来源白名单，以及内部服务没有被改成额外的 LoadBalancer。

## 排障

- 全部端口超时：运行 `route -n get 192.168.2.154`，确认走 OpenVPN 的 `utun7`，再核对白名单中的 `/32`。
- 浏览器报告证书不可信：将内部根 CA 加入 macOS 钥匙串并设为信任，不要忽略证书告警。
- 只有一个平台失败：查看 `platform-access` 命名空间的 Pod 日志和对应后端 Service。
- Argo 显示 504：确认 NetworkPolicy 允许到 `argocd` 命名空间的 TCP/8080。
- Observer 根路径 404：这是当前 Observer API 的正常行为，使用 `/health` 验证链路。
- Thunder 根路径 401：这是 Bearer 认证接口的正常行为，管理界面使用 `/console/`。

## 回滚

删除或禁用 Argo CD 的 `ip-access` Application 即可撤销这组入口；不要删除六个平台本身。
原域名入口与内部 ClusterIP 服务不依赖该网关。
