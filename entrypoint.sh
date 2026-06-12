#!/bin/sh
set -e

SOCKS_PORT="${HY2_SOCKS_PORT:-10808}"
HTTP_PORT="${HY2_HTTP_PORT:-10809}"
RULE_SET_DIR="/etc/sing-box/rule-set"
UPDATE_INTERVAL="${RULE_UPDATE_INTERVAL:-7d}"
RULE_SET_REPO="${RULE_SET_REPO:-https://github.com/DustinWin/ruleset_geodata/releases/latest/download}"

[ -z "$HY2_URI" ] && { echo "HY2_URI is required"; exit 1; }

# --- parse URI ---
URI="$HY2_URI"
URI="${URI#hysteria2://}"
URI="${URI#hy2://}"
URI="${URI%%#*}"
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
  1|true) INSECURE=true ;;
  *) INSECURE=false ;;
esac
[ -n "$PIN_SHA256" ] && INSECURE=true

# --- TLS block ---
TLS_BLOCK="{\"enabled\":true,\"server_name\":\"${SNI}\",\"insecure\":${INSECURE}}"

# --- build config.json ---
HOP_BLOCK=""
if [ -n "$MPORT" ]; then
  HOP_PORTS="$(echo "$MPORT" | tr '-' ':')"
  HOP_BLOCK=",\"server_ports\":[\"${HOP_PORTS}\"],\"hop_interval\":\"30s\""
fi

cat > /etc/sing-box/config.json <<JSONEOF
{
  "dns": {
    "servers": [
      {
        "tag": "dns-remote",
        "type": "udp",
        "server": "8.8.8.8",
        "detour": "hy2-proxy"
      },
      {
        "tag": "dns-local",
        "type": "udp",
        "server": "223.5.5.5",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "rule_set": ["cn"],
        "server": "dns-local"
      }
    ],
    "final": "dns-remote",
    "independent_cache": true
  },
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "::",
      "listen_port": ${SOCKS_PORT}
    },
    {
      "type": "http",
      "tag": "http-in",
      "listen": "::",
      "listen_port": ${HTTP_PORT}
    }
  ],
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-proxy",
      "server": "${SERVER}",
      "server_port": ${SERVER_PORT},
      "password": "${PASSWORD}",
      "tls": ${TLS_BLOCK}${HOP_BLOCK}
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "default_domain_resolver": {
      "server": "dns-local"
    },
    "rules": [
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "rule_set": ["cn", "cnip"],
        "outbound": "direct"
      },
      {
        "rule_set": ["private", "privateip"],
        "outbound": "direct"
      }
    ],
    "final": "hy2-proxy",
    "rule_set": [
      {
        "tag": "cn",
        "type": "local",
        "format": "binary",
        "path": "${RULE_SET_DIR}/cn.srs"
      },
      {
        "tag": "cnip",
        "type": "local",
        "format": "binary",
        "path": "${RULE_SET_DIR}/cnip.srs"
      },
      {
        "tag": "private",
        "type": "local",
        "format": "binary",
        "path": "${RULE_SET_DIR}/private.srs"
      },
      {
        "tag": "privateip",
        "type": "local",
        "format": "binary",
        "path": "${RULE_SET_DIR}/privateip.srs"
      }
    ]
  }
}
JSONEOF

echo "--- sing-box config ---"
cat /etc/sing-box/config.json
echo "-----------------------"

# --- rule-set updater ---
update_rules() {
  echo "$(date '+%F %T') Updating rule-sets via proxy..."
  PROXY="http://127.0.0.1:${HTTP_PORT}"
  for file in cn.srs cnip.srs private.srs privateip.srs gfw.srs; do
    curl -sf -x "$PROXY" "${RULE_SET_REPO}/${file}" -o "${RULE_SET_DIR}/${file}.tmp" && \
      mv "${RULE_SET_DIR}/${file}.tmp" "${RULE_SET_DIR}/${file}" && \
      echo "  Updated ${file}" || \
      echo "  Failed to update ${file}, keeping old"
  done
  # Reload sing-box config
  kill -HUP $(cat /run/sing-box.pid 2>/dev/null) 2>/dev/null && \
    echo "$(date '+%F %T') Rule-sets reloaded" || \
    echo "$(date '+%F %T') Reload failed"
}

# Start updater in background (wait for proxy to be ready first)
(
  sleep 10  # wait for sing-box to establish
  while true; do
    update_rules
    sleep "${UPDATE_INTERVAL}"
  done
) &

# Start sing-box
exec sing-box run -c /etc/sing-box/config.json
