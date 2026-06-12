#!/bin/sh
set -e

SOCKS_PORT="${HY2_SOCKS_PORT:-10808}"
HTTP_PORT="${HY2_HTTP_PORT:-10809}"

[ -z "$HY2_URI" ] && { echo "HY2_URI is required"; exit 1; }

# --- parse URI ---
URI="$HY2_URI"
URI="${URI#hysteria2://}"
URI="${URI#hy2://}"
FRAGMENT=""
case "$URI" in *#*) FRAGMENT="${URI#*#}"; URI="${URI%%#*}" ;; esac
USERINFO="${URI%%@*}"
REST="${URI#*@}"
HOSTPORT="${REST%%\?*}"
QUERY=""
case "$REST" in *\?*) QUERY="${REST#*\?}" ;; esac

PASSWORD="$(printf '%b' "$(echo "$USERINFO" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')")"
SERVER="${HOSTPORT%%:*}"
SERVER_PORT="${HOSTPORT##*:}"

get_param() { echo "$1" | tr '&' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

SNI="$(get_param "$QUERY" sni)"
INSECURE_RAW="$(get_param "$QUERY" insecure)"
MPORT="$(get_param "$QUERY" mport)"
PIN_SHA256="$(get_param "$QUERY" pinSHA256)"

case "$INSECURE_RAW" in
  1|true) SKIP_CERT_VERIFY=true ;;
  *) SKIP_CERT_VERIFY=false ;;
esac
[ -n "$PIN_SHA256" ] && SKIP_CERT_VERIFY=true

PROXY_NAME="${FRAGMENT:-hy2-proxy}"

# --- API secret ---
API_SECRET="${MIHOMO_SECRET:-$(cat /proc/sys/kernel/random/uuid)}"

# --- port hopping ---
PORTS_LINE=""
HOP_INTERVAL_LINE=""
if [ -n "$MPORT" ]; then
  PORTS_LINE="  ports: [\"${MPORT}\"]"
  HOP_INTERVAL_LINE="  hop-interval: 30"
fi

# --- generate config ---
cat > /etc/mihomo/config.yaml <<YAMLEOF
mixed-port: 0
allow-lan: true
mode: rule
log-level: info

external-controller: 0.0.0.0:9090
secret: "${API_SECRET}"

geodata-mode: true
geodata-loader: standard
geo-auto-update: false

geox-url:
  geoip: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
  geosite: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"

find-process-mode: strict

sniffer:
  enable: true
  sniff:
    HTTP:
      ports: [80, 8080-8880]
      override-destination: true
    TLS:
      ports: [443, 8443]
    QUIC:
      ports: [443, 8443]
  skip-domain:
    - "Mijia Cloud"
    - "+.push.apple.com"

dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - "*.lan"
    - "*.local"
    - "dns.msftncsi.com"
    - "www.msftncsi.com"
    - "www.msftconnecttest.com"
  default-nameserver:
    - 223.5.5.5
    - 114.114.114.114
  nameserver:
    - "https://doh.pub/dns-query"
    - "https://dns.alidns.com/dns-query"
  nameserver-policy:
    "geosite:cn,private":
      - "https://doh.pub/dns-query"
      - "https://dns.alidns.com/dns-query"
    "geosite:geolocation-!cn":
      - "https://dns.cloudflare.com/dns-query"
      - "https://dns.google/dns-query"

proxies:
  - name: "${PROXY_NAME}"
    type: hysteria2
    server: ${SERVER}
    port: ${SERVER_PORT}
    password: "${PASSWORD}"
    sni: "${SNI}"
    skip-cert-verify: ${SKIP_CERT_VERIFY}
${PORTS_LINE}
${HOP_INTERVAL_LINE}

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - ${PROXY_NAME}
      - DIRECT

rules:
  - GEOIP,private,DIRECT,no-resolve
  - GEOSITE,private,DIRECT
  - GEOSITE,cn,DIRECT
  - GEOIP,cn,DIRECT
  - MATCH,PROXY
YAMLEOF

# Clean empty lines from ports/hop-interval if not set
sed -i '/^$/d' /etc/mihomo/config.yaml

echo "--- mihomo config ---"
cat /etc/mihomo/config.yaml
echo "---------------------"
echo "API Secret: ${API_SECRET}"

exec mihomo -d /etc/mihomo
