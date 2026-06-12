#!/bin/sh
set -e

MIXED_PORT="${MIXED_PORT:-10808}"

# Check at least one URI is set
HAS_URI=false
env | grep -qE '^(HY2_URI|SS_URI|VLESS_URI)' && HAS_URI=true
[ "$HAS_URI" = "false" ] && { echo "At least one HY2_URI/VLESS_URI/SS_URI (or _1, _2...) is required"; exit 1; }

urldecode() { printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"; }
get_param() { echo "$1" | tr '&' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

PROXY_NAMES=""
PROXY_BLOCKS=""

# ============================================================
# Parse a single HY2 URI and append to PROXY_BLOCKS/PROXY_NAMES
# ============================================================
parse_hy2() {
  URI="$1"
  URI="${URI#hysteria2://}"; URI="${URI#hy2://}"
  FRAGMENT=""; case "$URI" in *#*) FRAGMENT="${URI#*#}"; URI="${URI%%#*}" ;; esac
  USERINFO="${URI%%@*}"; REST="${URI#*@}"
  HOSTPORT="${REST%%\?*}"; QUERY=""; case "$REST" in *\?*) QUERY="${REST#*\?}" ;; esac

  NAME="$(urldecode "$FRAGMENT")"; NAME="${NAME:-hy2-proxy}"

  BLOCK="  - name: \"${NAME}\"
    type: hysteria2
    server: ${HOSTPORT%%:*}
    port: ${HOSTPORT##*:}
    password: \"$(urldecode "$USERINFO")\""

  echo "$QUERY" | tr '&' '\n' | while IFS='=' read -r key val; do
    [ -z "$key" ] && continue
    val="$(urldecode "$val")"
    case "$key" in
      sni)           echo "    sni: \"${val}\"" ;;
      insecure|allowInsecure)
        case "$val" in 1|true) echo "    skip-cert-verify: true" ;; *) echo "    skip-cert-verify: false" ;; esac ;;
      pinSHA256)     ;; # mihomo hy2 does not support cert fingerprint pinning
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
  done | awk -F: '{key=$1} !seen[key]++ {print}' > /tmp/proxy_opts

  BLOCK="${BLOCK}
$(cat /tmp/proxy_opts)"
  rm -f /tmp/proxy_opts

  PROXY_NAMES="${PROXY_NAMES}      - ${NAME}
"
  PROXY_BLOCKS="${PROXY_BLOCKS}${BLOCK}
"
}

# ============================================================
# Parse a single SS URI
# ============================================================
parse_ss() {
  URI="$1"
  URI="${URI#ss://}"
  FRAGMENT=""; case "$URI" in *#*) FRAGMENT="${URI#*#}"; URI="${URI%%#*}" ;; esac
  NAME="$(urldecode "$FRAGMENT")"; NAME="${NAME:-ss-proxy}"

  USERINFO="${URI%%@*}"; REST="${URI#*@}"
  HOSTPORT="${REST%%\?*}"; QUERY=""; case "$REST" in *\?*) QUERY="${REST#*\?}" ;; esac
  SERVER="${HOSTPORT%%:*}"; PORT="${HOSTPORT##*:}"
  DECODED="$(echo "$USERINFO" | base64 -d 2>/dev/null || echo "$USERINFO")"
  METHOD="${DECODED%%:*}"; PASSWORD="${DECODED#*:}"

  BLOCK="  - name: \"${NAME}\"
    type: ss
    server: ${SERVER}
    port: ${PORT}
    cipher: ${METHOD}
    password: \"${PASSWORD}\""

  echo "$QUERY" | tr '&' '\n' | while IFS='=' read -r key val; do
    [ -z "$key" ] && continue
    val="$(urldecode "$val")"
    case "$key" in
      plugin)       echo "    plugin: ${val}" ;;
      udp)          echo "    udp: ${val}" ;;
      udp-over-tcp) echo "    udp-over-tcp: ${val}" ;;
    esac
  done > /tmp/proxy_opts

  BLOCK="${BLOCK}
$(cat /tmp/proxy_opts)"
  rm -f /tmp/proxy_opts

  PROXY_NAMES="${PROXY_NAMES}      - ${NAME}
"
  PROXY_BLOCKS="${PROXY_BLOCKS}${BLOCK}
"
}

# ============================================================
# Parse a single VLESS URI
# ============================================================
parse_vless() {
  URI="$1"
  URI="${URI#vless://}"
  FRAGMENT=""; case "$URI" in *#*) FRAGMENT="${URI#*#}"; URI="${URI%%#*}" ;; esac
  NAME="$(urldecode "$FRAGMENT")"; NAME="${NAME:-vless-proxy}"

  USERINFO="${URI%%@*}"; REST="${URI#*@}"
  HOSTPORT="${REST%%\?*}"; QUERY=""; case "$REST" in *\?*) QUERY="${REST#*\?}" ;; esac
  SERVER="${HOSTPORT%%:*}"; PORT="${HOSTPORT##*:}"
  UUID="$USERINFO"

  NET="$(get_param "$QUERY" type)"; NET="${NET:-tcp}"
  SEC="$(get_param "$QUERY" security)"; SEC="${SEC:-none}"
  PATH_P="$(get_param "$QUERY" path)"
  HOST_P="$(get_param "$QUERY" host)"
  SNI="$(get_param "$QUERY" sni)"
  FP="$(get_param "$QUERY" fp)"
  PBK="$(get_param "$QUERY" pbk)"
  SID="$(get_param "$QUERY" sid)"

  BLOCK="  - name: \"${NAME}\"
    type: vless
    server: ${SERVER}
    port: ${PORT}
    uuid: ${UUID}
    network: ${NET}"

  # Iterate generic params
  echo "$QUERY" | tr '&' '\n' | while IFS='=' read -r key val; do
    [ -z "$key" ] && continue
    val="$(urldecode "$val")"
    case "$key" in
      flow)             echo "    flow: ${val}" ;;
      alpn)             echo "    alpn: [${val}]" ;;
      encryption)       echo "    encryption: ${val}" ;;
      packet-encoding)  echo "    packet-encoding: ${val}" ;;
      type|security|path|host|sni|servername|fp|pbk|sid) ;; # handled below
    esac
  done > /tmp/proxy_opts

  # TLS block
  case "$SEC" in
    tls)
      echo "    tls: true" >> /tmp/proxy_opts
      [ -n "$SNI" ] && echo "    servername: \"${SNI}\"" >> /tmp/proxy_opts
      [ -n "$FP" ] && echo "    client-fingerprint: ${FP}" >> /tmp/proxy_opts
      ;;
    reality)
      echo "    tls: true" >> /tmp/proxy_opts
      [ -n "$SNI" ] && echo "    servername: \"${SNI}\"" >> /tmp/proxy_opts
      [ -n "$FP" ] && echo "    client-fingerprint: ${FP}" >> /tmp/proxy_opts
      echo "    reality-opts:" >> /tmp/proxy_opts
      [ -n "$PBK" ] && echo "      public-key: \"${PBK}\"" >> /tmp/proxy_opts
      [ -n "$SID" ] && echo "      short-id: \"${SID}\"" >> /tmp/proxy_opts
      ;;
  esac

  # Transport block
  case "$NET" in
    ws)
      echo "    ws-opts:" >> /tmp/proxy_opts
      [ -n "$PATH_P" ] && echo "      path: \"$(urldecode "$PATH_P")\"" >> /tmp/proxy_opts
      [ -n "$HOST_P" ] && echo "      headers:" >> /tmp/proxy_opts && echo "        Host: \"${HOST_P}\"" >> /tmp/proxy_opts
      ;;
    grpc)
      echo "    grpc-opts:" >> /tmp/proxy_opts
      [ -n "$PATH_P" ] && echo "      grpc-service-name: \"$(urldecode "$PATH_P")\"" >> /tmp/proxy_opts
      ;;
  esac

  BLOCK="${BLOCK}
$(cat /tmp/proxy_opts)"
  rm -f /tmp/proxy_opts

  PROXY_NAMES="${PROXY_NAMES}      - ${NAME}
"
  PROXY_BLOCKS="${PROXY_BLOCKS}${BLOCK}
"
}

# ============================================================
# Iterate all matching env vars
# ============================================================
for var in $(env | grep -E '^(HY2_URI|SS_URI|VLESS_URI)' | cut -d= -f1 | sort); do
  val="$(eval echo "\$$var")"
  [ -z "$val" ] && continue
  case "$var" in
    HY2_URI*)   parse_hy2 "$val" ;;
    SS_URI*)    parse_ss "$val" ;;
    VLESS_URI*) parse_vless "$val" ;;
  esac
done

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
