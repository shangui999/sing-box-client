# sing-box-client

Dockerized sing-box with Hysteria 2 outbound and CN split routing.

## Features

- Single container, sing-box natively supports Hysteria 2
- Built-in split routing: CN traffic direct, everything else via hy2
- DNS split: CN domains via local DNS, others via remote DNS through proxy
- Pre-loaded rule-sets from [DustinWin/ruleset_geodata](https://github.com/DustinWin/ruleset_geodata)
- Runtime auto-update rule-sets via proxy (every 7 days by default)

## Quick Start (docker-compose)

```yaml
services:
  sing-box:
    image: ghcr.io/shangui999/sing-box-client:latest
    container_name: sing-box-client
    restart: always
    environment:
      - HY2_URI=hysteria2://YOUR_PASSWORD@YOUR_SERVER:PORT?sni=example.com&insecure=0&mport=50000-60000&pinSHA256=YOUR_PIN
      - HY2_SOCKS_PORT=10808
      - HY2_HTTP_PORT=10809
    ports:
      - "10808:10808"
      - "10809:10809"
```

## Quick Start (docker run)

```bash
docker run -d --name sing-box-client --restart always \
  -e HY2_URI="hysteria2://password@server:port?sni=example.com&insecure=0" \
  -p 10808:10808 -p 10809:10809 \
  ghcr.io/shangui999/sing-box-client:latest
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `HY2_URI` | Yes | - | Full hysteria2:// URI |
| `HY2_SOCKS_PORT` | No | `10808` | SOCKS5 proxy listen port |
| `HY2_HTTP_PORT` | No | `10809` | HTTP proxy listen port |
| `RULE_UPDATE_INTERVAL` | No | `7d` | Rule-set update interval (e.g. `1d`, `12h`) |

## Routing Rules

| Traffic | Action |
|---------|--------|
| CN domains/IPs | Direct |
| Private domains/IPs | Direct |
| Everything else | hy2 proxy |

## DNS

| Query | Server | Path |
|-------|--------|------|
| CN domains | 223.5.5.5 (AliDNS) | Direct |
| Others | 8.8.8.8 (Google) | Via hy2 proxy |

## Upgrade Hysteria 2 / sing-box Version

Edit versions in `Dockerfile`, push to main — GitHub Actions will auto-build and push the new image.

## Rule-set Auto-Update

Rule-sets are built into the image at build time. After the container starts, a background process updates them every 7 days (configurable via `RULE_UPDATE_INTERVAL`) by downloading through the proxy itself.

## License

MIT
