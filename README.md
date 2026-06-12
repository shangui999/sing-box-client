# mihomo-client

基于 mihomo (Clash Meta) 的 Docker 化代理客户端，支持 Hysteria 2 / VLESS / Shadowsocks 多协议，内置国内流量分流。

## 特性

- 单容器，mihomo 原生支持 Hy2 / VLESS / SS 等多种协议
- 混合端口：一个端口同时支持 HTTP 和 SOCKS5
- 内置分流规则：国内流量直连，其余走代理
- DNS 分流 + fake-ip 模式，防 DNS 污染
- GeoIP/GeoSite 规则每 24 小时自动更新
- 支持端口跳跃 (port hopping)
- 构建时自动拉取最新 mihomo 版本
- API 认证保护
- 支持多代理同时配置，面板切换

## 快速开始 (docker-compose)

```yaml
services:
  mihomo:
    image: ghcr.io/shangui999/mihomo-client:latest
    container_name: mihomo-client
    restart: always
    environment:
      - HY2_URI=hysteria2://YOUR_PASSWORD@SERVER1:PORT?sni=example.com&insecure=1#hy2-node1
      - HY2_URI_1=hysteria2://YOUR_PASSWORD@SERVER2:PORT?sni=example.com&insecure=1#hy2-node2
      - VLESS_URI=vless://UUID@SERVER:PORT?type=tcp&security=reality&sni=example.com&fp=chrome&pbk=KEY&sid=ID&flow=xtls-rprx-vision#vless-node1
      - SS_URI=ss://BASE64@SERVER:PORT#ss-node1
    ports:
      - "10808:10808"   # 混合端口 (HTTP + SOCKS5)
      - "9090:9090"     # 管理面板 API
```

## 快速开始 (docker run)

```bash
docker run -d --name mihomo-client --restart always \
  -e HY2_URI="hysteria2://password@server:port?sni=example.com&insecure=1" \
  -p 10808:10808 -p 9090:9090 \
  ghcr.io/shangui999/mihomo-client:dev
```

## 环境变量

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `HY2_URI` | 至少一个 | - | Hysteria 2 URI |
| `HY2_URI_1` / `HY2_URI_2` / ... | 可选 | - | 更多 HY2 节点 |
| `VLESS_URI` | 至少一个 | - | VLESS URI |
| `VLESS_URI_1` / `VLESS_URI_2` / ... | 可选 | - | 更多 VLESS 节点 |
| `SS_URI` | 至少一个 | - | Shadowsocks URI |
| `SS_URI_1` / `SS_URI_2` / ... | 可选 | - | 更多 SS 节点 |
| `MIXED_PORT` | 否 | `10808` | 混合端口，同时支持 HTTP 和 SOCKS5 |
| `MIHOMO_SECRET` | 否 | 随机 UUID | 管理面板 API 认证密钥 |

> 至少设置一个 URI 变量。同协议可设置多个（如 `VLESS_URI_1`、`VLESS_URI_2`），在管理面板中切换。

## 支持的协议和参数

### Hysteria 2 (`HY2_URI`)

URI 格式：`hysteria2://password@server:port?params#name`

| 参数 | 说明 | 示例 |
|------|------|------|
| `sni` | TLS SNI 域名 | `sni=bing.com` |
| `insecure` | 跳过证书验证 (0/1) | `insecure=1` |
| `allowInsecure` | 同 insecure | `allowInsecure=1` |
| `mport` | 端口跳跃范围 | `mport=50000-60000` |
| `hop-interval` | 端口跳跃间隔(秒) | `hop-interval=30` |
| `up` | 上行带宽 (brutal) | `up=100mbps` |
| `down` | 下行带宽 (brutal) | `down=100mbps` |
| `obfs` | 混淆类型 | `obfs=salamander` |
| `obfs-password` | 混淆密码 | `obfs-password=xxx` |
| `cwnd` | 拥塞窗口 | `cwnd=100` |
| `alpn` | ALPN 协议 | `alpn=h3` |
| `fingerprint` | TLS 指纹 | `fingerprint=chrome` |
| `#name` | 代理名称 | `#my-hy2` |

> 注意：pinSHA256 证书指纹校验 mihomo 暂不支持 hy2，已通过 insecure 跳过验证。

### VLESS (`VLESS_URI`)

URI 格式：`vless://uuid@server:port?params#name`

| 参数 | 说明 | 示例 |
|------|------|------|
| `type` | 传输协议 | `type=tcp` / `ws` / `grpc` |
| `security` | 安全层 | `security=tls` / `reality` / `none` |
| `sni` | TLS SNI 域名 | `sni=example.com` |
| `fp` | 客户端指纹 | `fp=chrome` / `firefox` |
| `flow` | 流控 | `flow=xtls-rprx-vision` |
| `pbk` | Reality 公钥 | `pbk=xxx` |
| `sid` | Reality short-id | `sid=xxx` |
| `path` | WS/gRPC 路径 | `path=%2Fws` |
| `host` | WS Host 头 | `host=example.com` |
| `alpn` | ALPN 协议 | `alpn=h2,http/1.1` |
| `encryption` | 加密方式 | `encryption=none` |
| `#name` | 代理名称 | `#my-vless` |

### Shadowsocks (`SS_URI`)

URI 格式：`ss://base64(cipher:password)@server:port?params#name`

| 参数 | 说明 | 示例 |
|------|------|------|
| `plugin` | 插件 | `plugin=obfs-local` |
| `udp` | 启用 UDP | `udp=true` |
| `udp-over-tcp` | UDP over TCP | `udp-over-tcp=true` |
| `#name` | 代理名称 | `#my-ss` |

支持的加密方式：aes-128-gcm, aes-256-gcm, chacha20-ietf-poly1305, 2022-blake3-aes-128-gcm, 2022-blake3-aes-256-gcm 等。

## 使用方式

### 作为 HTTP 代理

```bash
curl -x http://YOUR_HOST_IP:10808 https://www.google.com
export http_proxy=http://YOUR_HOST_IP:10808
export https_proxy=http://YOUR_HOST_IP:10808
```

### 作为 SOCKS5 代理

```bash
curl -x socks5h://YOUR_HOST_IP:10808 https://www.google.com
```

### 在浏览器/系统中配置

- 代理类型：SOCKS5 或 HTTP
- 地址：`YOUR_HOST_IP`
- 端口：`10808`

## 分流规则

从上到下依次匹配，命中即停止：

| 顺序 | 匹配条件 | 动作 |
|------|----------|------|
| 1 | 私有 IP (192.168.x, 10.x 等) | 直连 |
| 2 | 私有域名 (.local, .lan 等) | 直连 |
| 3 | 国内域名 (geosite:cn) | 直连 |
| 4 | 国内 IP (geoip:cn) | 直连 |
| 5 | 其余所有流量 | 走代理 |

规则数据库来源：[MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat)，每 24 小时自动更新。

## DNS 配置

| 查询类型 | DNS 服务器 | 路径 |
|----------|-----------|------|
| 默认 (解析 DoH 域名) | 223.5.5.5 / 114.114.114.114 | 直连 UDP |
| 国内/私有域名 | DoH (doh.pub, alidns) | 直连 |
| 国外域名 | DoH (cloudflare, google) | 经代理 |

使用 fake-ip 模式，mihomo 直接返回 `198.18.x.x` 假 IP，实际 DNS 查询在连接建立时异步完成，避免 DNS 泄露和污染。

## 管理面板

容器启动日志会打印 API Secret。通过 9090 端口访问面板：

- [Yacd](http://yacd.haishan.me/?hostname=YOUR_HOST_IP&port=9090)
- [MetaCubeX Dashboard](http://d.metacubex.one/?hostname=YOUR_HOST_IP&port=9090)

连接时需填入 Secret 认证。可通过环境变量 `MIHOMO_SECRET` 设置固定密钥。

## 镜像标签

| 标签 | 分支 | 说明 |
|------|------|------|
| `latest` | main | 稳定版，支持 HY2 + VLESS + SS 多协议 + 多节点 |
| `dev` | dev | 开发版，与 main 同步 |

## CI/CD

- push 到 `main` → 自动构建并推送 `latest` 标签
- push 到 `dev` → 自动构建并推送 `dev` 标签
- mihomo 版本构建时自动获取最新 release

## 许可证

MIT
