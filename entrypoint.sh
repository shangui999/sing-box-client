#!/bin/sh
set -e

MIXED_PORT="${MIXED_PORT:-10808}"

[ -z "$HY2_URI" ] && [ -z "$SS_URI" ] && [ -z "$VLESS_URI" ] && { echo "At least one of HY2_URI, SS_URI, VLESS_URI is required"; exit 1; }

urldecode() { printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"; }
get_param() { echo "$1" | tr '&' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

PROXY_NAMES=""
PROXY_BLOCKS=""

# --- parse HY2_URI ---
if [ -n "$HY2_URI" ]; then
  URI="$HY2_URI"
  URI="${URI#hysteria2://}"; URI="${URI#hy2://}"
  FRAGMENT=""; case "$URI" in *#*) FRAGMENT="${URI#*#}"; URI="${URI%%#*}" ;; esac
  USERINFO="${URI%%@*}"; REST="${URI#*@}"
  HOSTPORT="${REST%%\?*}"; QUERY=""; case "$REST" in *\?*) QUERY="${REST#*\?}" ;; esac
  HY2_PASSWORD="$(urldecode "$USERINFO")"
  HY2_SERVER="${HOSTPORT%%:*}"; HY2_PORT="${HOSTPORT##*:}"
  HY2_SNI="$(get_param "$QUERY" sni)"
  HY2_INSECURE_RAW="$(get_param "$QUERY" insecure)"
  HY2_MPORT="$(get_param "$QUERY" mport)"
  HY2_PIN="$(get_param "$QUERY" pinSHA256)"
  case "$HY2_INSECURE_RAW" in 1|true) HY2_SKIP=true ;; *) HY2_SKIP=false ;; esac
  [ -n "$HY2_PIN" ] && HY2_SKIP=true
  HY2_NAME="${FRAGMENT:-hy2-proxy}"
  HY2_PORTS=""; HY2_HOP=""; HY2_CERT=""
  if [ -n "$HY2_MPORT" ]; then
    HY2_PORTS="    ports: \"${HY2_MPORT}\""
    HY2_HOP="    hop-interval: 30"
  fi
  [ -n "$HY2_PIN" ] && HY2_CERT="    certificate: \"${HY2_PIN}\""

  PROXY_NAMES="${PROXY_NAMES}      - ${HY2_NAME}
"
  PROXY_BLOCKS="${PROXY_BLOCKS}  - name: \"${HY2_NAME}\"
    type: hysteria2
    server: ${HY2_SERVER}
    port: ${HY2_PORT}
    password: \"${HY2_PASSWORD}\"
    sni: \"${HY2_SNI}\"
    skip-cert-verify: ${HY2_SKIP}
${HY2_CERT}
${HY2_PORTS}
${HY2_HOP}
"
fi

# --- parse SS_URI ---
if [ -n "$SS_URI" ]; then
  URI="$SS_URI"
  URI="${URI#ss://}"
  SS_FRAGMENT=""; case "$URI" in *#*) SS_FRAGMENT="${URI#*#}"; URI="${URI%%#*}" ;; esac
  # ss://base64(method:password)@server:port or ss://method:password@server:port
  USERINFO="${URI%%@*}"; REST="${URI#*@}"
  SS_HOSTPORT="${REST%%\?*}"
  SS_SERVER="${SS_HOSTPORT%%:*}"; SS_PORT="${SS_HOSTPORT##*:}"
  # Try base64 decode first
  SS_DECODED="$(echo "$USERINFO" | base64 -d 2>/dev/null || echo "$USERINFO")"
  SS_METHOD="${SS_DECODED%%:*}"; SS_PASSWORD="${SS_DECODED#*:}"
  SS_NAME="$(urldecode "$SS_FRAGMENT")"; SS_NAME="${SS_NAME:-ss-proxy}"

  PROXY_NAMES="${PROXY_NAMES}      - ${SS_NAME}
"
  PROXY_BLOCKS="${PROXY_BLOCKS}  - name: \"${SS_NAME}\"
    type: ss
    server: ${SS_SERVER}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: \"${SS_PASSWORD}\"
"
fi

# --- parse VLESS_URI ---
if [ -n "$VLESS_URI" ]; then
  URI="$VLESS_URI"
  URI="${URI#vless://}"
  VL_FRAGMENT=""; case "$URI" in *#*) VL_FRAGMENT="${URI#*#}"; URI="${URI%%#*}" ;; esac
  USERINFO="${URI%%@*}"; REST="${URI#*@}"
  VL_HOSTPORT="${REST%%\?*}"; VL_QUERY=""; case "$REST" in *\?*) VL_QUERY="${REST#*\?}" ;; esac
  VL_UUID="$USERINFO"
  VL_SERVER="${VL_HOSTPORT%%:*}"; VL_PORT="${VL_HOSTPORT##*:}"
  VL_TYPE="$(get_param "$VL_QUERY" type)"; VL_TYPE="${VL_TYPE:-tcp}"
  VL_SECURITY="$(get_param "$VL_QUERY" security)"; VL_SECURITY="${VL_SECURITY:-tls}"
  VL_SNI="$(get_param "$VL_QUERY" sni)"
  VL_FLOW="$(get_param "$VL_QUERY" flow)"
  VL_PATH="$(get_param "$VL_QUERY" path)"
  VL_HOST="$(get_param "$VL_QUERY" host)"
  VL_PBK="$(get_param "$VL_QUERY" pbk)"
  VL_SID="$(get_param "$VL_QUERY" sid)"
  VL_FP="$(get_param "$VL_QUERY" fp)"; VL_FP="${VL_FP:-chrome}"
  VL_NAME="$(urldecode "$VL_FRAGMENT")"; VL_NAME="${VL_NAME:-vless-proxy}"

  # Build network/transport block
  VL_NET_BLOCK="    network: ${VL_TYPE}"
  case "$VL_TYPE" in
    ws)
      VL_WS_PATH="$(urldecode "$VL_PATH")"
      VL_NET_BLOCK="${VL_NET_BLOCK}
    ws-opts:
      path: \"${VL_WS_PATH}\"
      headers:
        Host: \"${VL_HOST}\""
      ;;
    grpc)
      VL_NET_BLOCK="${VL_NET_BLOCK}
    grpc-opts:
      grpc-service-name: \"${VL_PATH}\""
      ;;
  esac

  # Build TLS block
  VL_TLS_BLOCK=""
  case "$VL_SECURITY" in
    tls)
      VL_TLS_BLOCK="    tls: true
    sni: \"${VL_SNI}\"
    client-fingerprint: ${VL_FP}"
      ;;
    reality)
      VL_TLS_BLOCK="    tls: true
    sni: \"${VL_SNI}\"
    client-fingerprint: ${VL_FP}
    reality-opts:
      public-key: \"${VL_PBK}\"
      short-id: \"${VL_SID}\""
      ;;
  esac

  # Flow
  VL_FLOW_LINE=""; [ -n "$VL_FLOW" ] && VL_FLOW_LINE="    flow: ${VL_FLOW}"

  PROXY_NAMES="${PROXY_NAMES}      - ${VL_NAME}
"
  PROXY_BLOCKS="${PROXY_BLOCKS}  - name: \"${VL_NAME}\"
    type: vless
    server: ${VL_SERVER}
    port: ${VL_PORT}
    uuid: ${VL_UUID}
${VL_FLOW_LINE}
${VL_NET_BLOCK}
${VL_TLS_BLOCK}
"
fi

# --- API secret ---
API_SECRET="${MIHOMO_SECRET:-$(cat /proc/sys/kernel/random/uuid)}"

# --- generate config ---
cat > /etc/mihomo/config.yaml <<YAMLEOF
mixed-port: ${MIXED_PORT}
allow-lan: true
mode: rule
log-level: info

external-controller: 0.0.0.0:9090
secret: "${API_SECRET}"

geodata-mode: true
geodata-loader: standard
geo-auto-update: true
geo-update-interval: 24

geox-url:
  geoip: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
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
${PROXY_BLOCKS}
proxy-groups:
  - name: PROXY
    type: select
    proxies:
${PROXY_NAMES}      - DIRECT

rules:
  - GEOIP,private,DIRECT,no-resolve
  - GEOSITE,private,DIRECT
  - GEOSITE,cn,DIRECT
  - GEOIP,cn,DIRECT
  - MATCH,PROXY
YAMLEOF

# Clean empty lines
sed -i '/^$/d' /etc/mihomo/config.yaml

echo "--- mihomo config ---"
cat /etc/mihomo/config.yaml
echo "---------------------"
echo "API Secret: ${API_SECRET}"

exec mihomo -d /etc/mihomo
