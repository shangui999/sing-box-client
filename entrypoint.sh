#!/bin/sh
set -e

MIXED_PORT="${MIXED_PORT:-10808}"

[ -z "$HY2_URI" ] && [ -z "$SS_URI" ] && [ -z "$VLESS_URI" ] && { echo "At least one of HY2_URI, SS_URI, VLESS_URI is required"; exit 1; }

urldecode() { printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"; }
get_param() { echo "$1" | tr '&' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

PROXY_NAMES=""
PROXY_BLOCKS=""

# ============================================================
# Parse HY2_URI
# ============================================================
if [ -n "$HY2_URI" ]; then
  URI="$HY2_URI"
  URI="${URI#hysteria2://}"; URI="${URI#hy2://}"
  FRAGMENT=""; case "$URI" in *#*) FRAGMENT="${URI#*#}"; URI="${URI%%#*}" ;; esac
  USERINFO="${URI%%@*}"; REST="${URI#*@}"
  HOSTPORT="${REST%%\?*}"; QUERY=""; case "$REST" in *\?*) QUERY="${REST#*\?}" ;; esac

  HY2_NAME="$(urldecode "$FRAGMENT")"; HY2_NAME="${HY2_NAME:-hy2-proxy}"

  # Build proxy block by iterating all query params
  HY2_BLOCK="  - name: \"${HY2_NAME}\"
    type: hysteria2
    server: ${HOSTPORT%%:*}
    port: ${HOSTPORT##*:}
    password: \"$(urldecode "$USERINFO")\""

  echo "$QUERY" | tr '&' '\n' | while IFS='=' read -r key val; do
    [ -z "$key" ] && continue
    val="$(urldecode "$val")"
    case "$key" in
      sni)           echo "    sni: \"${val}\"" ;;
      insecure)
        case "$val" in 1|true) echo "    skip-cert-verify: true" ;; *) echo "    skip-cert-verify: false" ;; esac ;;
      pinSHA256)     echo "    certificate: \"${val}\"
    skip-cert-verify: true" ;;
      mport)         echo "    ports: \"${val}\"" ;;
      hop-interval)  echo "    hop-interval: ${val}" ;;
      up)            echo "    up: \"${val}\"" ;;
      down)          echo "    down: \"${val}\"" ;;
      obfs)          echo "    obfs: ${val}" ;;
      obfs-password) echo "    obfs-password: \"${val}\"" ;;
      cwnd)          echo "    cwnd: ${val}" ;;
      alpn)          echo "    alpn: [${val}]" ;;
      fingerprint)   echo "    fingerprint: ${val}" ;;
    esac
  done > /tmp/hy2_opts

  HY2_BLOCK="${HY2_BLOCK}
$(cat /tmp/hy2_opts)"
  rm -f /tmp/hy2_opts

  PROXY_NAMES="${PROXY_NAMES}      - ${HY2_NAME}
"
  PROXY_BLOCKS="${PROXY_BLOCKS}${HY2_BLOCK}
"
fi

# ============================================================
# Parse SS_URI
# ============================================================
if [ -n "$SS_URI" ]; then
  URI="$SS_URI"
  URI="${URI#ss://}"
  SS_FRAGMENT=""; case "$URI" in *#*) SS_FRAGMENT="${URI#*#}"; URI="${URI%%#*}" ;; esac
  SS_NAME="$(urldecode "$SS_FRAGMENT")"; SS_NAME="${SS_NAME:-ss-proxy}"

  USERINFO="${URI%%@*}"; REST="${URI#*@}"
  SS_HOSTPORT="${REST%%\?*}"; SS_QUERY=""; case "$REST" in *\?*) SS_QUERY="${REST#*\?}" ;; esac
  SS_SERVER="${SS_HOSTPORT%%:*}"; SS_PORT="${SS_HOSTPORT##*:}"
  SS_DECODED="$(echo "$USERINFO" | base64 -d 2>/dev/null || echo "$USERINFO")"
  SS_METHOD="${SS_DECODED%%:*}"; SS_PASSWORD="${SS_DECODED#*:}"

  SS_BLOCK="  - name: \"${SS_NAME}\"
    type: ss
    server: ${SS_SERVER}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: \"${SS_PASSWORD}\""

  echo "$SS_QUERY" | tr '&' '\n' | while IFS='=' read -r key val; do
    [ -z "$key" ] && continue
    val="$(urldecode "$val")"
    case "$key" in
      plugin)      echo "    plugin: ${val}" ;;
      udp)         echo "    udp: ${val}" ;;
      udp-over-tcp) echo "    udp-over-tcp: ${val}" ;;
    esac
  done > /tmp/ss_opts

  SS_BLOCK="${SS_BLOCK}
$(cat /tmp/ss_opts)"
  rm -f /tmp/ss_opts

  PROXY_NAMES="${PROXY_NAMES}      - ${SS_NAME}
"
  PROXY_BLOCKS="${PROXY_BLOCKS}${SS_BLOCK}
"
fi

# ============================================================
# Parse VLESS_URI
# ============================================================
if [ -n "$VLESS_URI" ]; then
  URI="$VLESS_URI"
  URI="${URI#vless://}"
  VL_FRAGMENT=""; case "$URI" in *#*) VL_FRAGMENT="${URI#*#}"; URI="${URI%%#*}" ;; esac
  VL_NAME="$(urldecode "$VL_FRAGMENT")"; VL_NAME="${VL_NAME:-vless-proxy}"

  USERINFO="${URI%%@*}"; REST="${URI#*@}"
  VL_HOSTPORT="${REST%%\?*}"; VL_QUERY=""; case "$REST" in *\?*) VL_QUERY="${REST#*\?}" ;; esac
  VL_SERVER="${VL_HOSTPORT%%:*}"; VL_PORT="${VL_HOSTPORT##*:}"
  VL_UUID="$USERINFO"

  # Pre-parse needed fields
  VL_NET="$(get_param "$VL_QUERY" type)"; VL_NET="${VL_NET:-tcp}"
  VL_SEC="$(get_param "$VL_QUERY" security)"; VL_SEC="${VL_SEC:-none}"
  VL_PATH="$(get_param "$VL_QUERY" path)"
  VL_HOST="$(get_param "$VL_QUERY" host)"

  VL_BLOCK="  - name: \"${VL_NAME}\"
    type: vless
    server: ${VL_SERVER}
    port: ${VL_PORT}
    uuid: ${VL_UUID}
    network: ${VL_NET}"

  # Iterate all query params
  echo "$VL_QUERY" | tr '&' '\n' | while IFS='=' read -r key val; do
    [ -z "$key" ] && continue
    val="$(urldecode "$val")"
    case "$key" in
      flow)             echo "    flow: ${val}" ;;
      sni|servername)   echo "    servername: \"${val}\"" ;;
      fp)               echo "    client-fingerprint: ${val}" ;;
      alpn)             echo "    alpn: [${val}]" ;;
      encryption)       echo "    encryption: ${val}" ;;
      packet-encoding)  echo "    packet-encoding: ${val}" ;;
      pbk)              echo "    pbk: ${val}" ;;
      sid)              echo "    sid: ${val}" ;;
      type|security|path|host) ;; # handled separately below
    esac
  done > /tmp/vl_opts

  # TLS block based on security type
  VL_SNI="$(get_param "$VL_QUERY" sni)"
  VL_FP="$(get_param "$VL_QUERY" fp)"
  VL_PBK="$(get_param "$VL_QUERY" pbk)"
  VL_SID="$(get_param "$VL_QUERY" sid)"

  case "$VL_SEC" in
    tls)
      echo "    tls: true" >> /tmp/vl_opts
      [ -n "$VL_SNI" ] && echo "    servername: \"${VL_SNI}\"" >> /tmp/vl_opts
      [ -n "$VL_FP" ] && echo "    client-fingerprint: ${VL_FP}" >> /tmp/vl_opts
      ;;
    reality)
      echo "    tls: true" >> /tmp/vl_opts
      [ -n "$VL_SNI" ] && echo "    servername: \"${VL_SNI}\"" >> /tmp/vl_opts
      [ -n "$VL_FP" ] && echo "    client-fingerprint: ${VL_FP}" >> /tmp/vl_opts
      echo "    reality-opts:" >> /tmp/vl_opts
      [ -n "$VL_PBK" ] && echo "      public-key: \"${VL_PBK}\"" >> /tmp/vl_opts
      [ -n "$VL_SID" ] && echo "      short-id: \"${VL_SID}\"" >> /tmp/vl_opts
      ;;
  esac

  # Transport opts based on network type
  case "$VL_NET" in
    ws)
      echo "    ws-opts:" >> /tmp/vl_opts
      [ -n "$VL_PATH" ] && echo "      path: \"$(urldecode "$VL_PATH")\"" >> /tmp/vl_opts
      [ -n "$VL_HOST" ] && echo "      headers:" >> /tmp/vl_opts && echo "        Host: \"${VL_HOST}\"" >> /tmp/vl_opts
      ;;
    grpc)
      echo "    grpc-opts:" >> /tmp/vl_opts
      [ -n "$VL_PATH" ] && echo "      grpc-service-name: \"$(urldecode "$VL_PATH")\"" >> /tmp/vl_opts
      ;;
  esac

  VL_BLOCK="${VL_BLOCK}
$(cat /tmp/vl_opts)"
  rm -f /tmp/vl_opts

  PROXY_NAMES="${PROXY_NAMES}      - ${VL_NAME}
"
  PROXY_BLOCKS="${PROXY_BLOCKS}${VL_BLOCK}
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
