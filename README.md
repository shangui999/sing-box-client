# mihomo-client

基于 mihomo (Clash Meta) 的 Docker 化 Hysteria 2 客户端，内置国内流量分流。

## 特性

- 单容器，mihomo 原生支持 Hysteria 2
- 内置分流规则：国内流量直连，其余走代理
- DNS 分流 + fake-ip 模式，防 DNS 污染
- 支持端口跳跃 (port hopping)
- 构建时自动拉取最新 mihomo 版本
- 内置 GeoIP/GeoSite 规则数据库

## 快速开始 (docker-compose)

```yaml
services:
  mihomo:
    image: ghcr.io/shangui999/mihomo-client:latest
    container_name: mihomo-client
    restart: always
    environment:
      - HY2_URI=hysteria2://YOUR_PASSWORD@YOUR_SERVER:PORT?sni=example.com&insecure=0&mport=50000-60000#my-proxy
      - HY2_SOCKS_PORT=10808
      - HY2_HTTP_PORT=10809
    ports:
      - "10808:10808"   # SOCKS5
      - "10809:10809"   # HTTP
      - "9090:9090"     # 管理面板 API
```

## 快速开始 (docker run)

```bash
docker run -d --name mihomo-client --restart always \
  -e HY2_URI="hysteria2://password@server:port?sni=example.com&insecure=0" \
  -p 10808:10808 -p 10809:10809 \
  ghcr.io/shangui999/mihomo-client:latest
```

## 环境变量

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `HY2_URI` | 是 | - | 完整的 hysteria2:// URI |
| `HY2_SOCKS_PORT` | 否 | `10808` | SOCKS5 代理监听端口 |
| `HY2_HTTP_PORT` | 否 | `10809` | HTTP 代理监听端口 |

## 分流规则

从上到下依次匹配，命中即停止：

| 顺序 | 匹配条件 | 动作 |
|------|----------|------|
| 1 | 私有 IP (192.168.x, 10.x 等) | 直连 |
| 2 | 私有域名 (.local, .lan 等) | 直连 |
| 3 | 国内域名 (geosite:cn) | 直连 |
| 4 | 国内 IP (geoip:cn) | 直连 |
| 5 | 其余所有流量 | 走 hy2 代理 |

规则数据库来源：[MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat)

## DNS 配置

| 查询类型 | DNS 服务器 | 路径 |
|----------|-----------|------|
| 默认 (解析 DoH 域名) | 223.5.5.5 / 114.114.114.114 | 直连 UDP |
| 国内/私有域名 | DoH (doh.pub, alidns) | 直连 |
| 国外域名 | DoH (cloudflare, google) | 经 hy2 代理 |

使用 fake-ip 模式，mihomo 直接返回 `198.18.x.x` 假 IP，实际 DNS 查询在连接建立时异步完成，避免 DNS 泄露和污染。

## URI 参数说明

| 参数 | 说明 | 示例 |
|------|------|------|
| `sni` | TLS SNI 域名 | `sni=bing.com` |
| `insecure` | 跳过证书验证 (0/1) | `insecure=1` |
| `mport` | 端口跳跃范围 | `mport=50000-60000` |
| `pinSHA256` | 证书指纹校验 | `pinSHA256=xxx` |
| `#name` | 代理名称 (fragment) | `#my-proxy` |

## 管理面板

容器启动后可通过 `9090` 端口访问 Clash API：

- Yacd: http://yacd.haishan.me/?hostname=192.168.1.200&port=9090
- MetaCubeX Dashboard: http://d.metacubex.one/?hostname=192.168.1.200&port=9090

## 升级 mihomo 版本

修改代码后 push 到 main，GitHub Actions 自动构建最新镜像。

## 许可证

MIT
