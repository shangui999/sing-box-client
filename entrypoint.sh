#!/bin/sh
set -e

SOCKS_PORT="${HY2_SOCKS_PORT:-10808}"
HTTP_PORT="${HY2_HTTP_PORT:-10809}"

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

# --- build config.json ---
TLS_BLOCK="{\"enabled\":true,\"server_name\":\"${SNI}\",\"insecure\":${INSECURE}}"

# Use jq if available, otherwise manual JSON
cat > /etc/sing-box/config.json <<JSONEOF
{
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
      "password": "${PASSWORD}"${HY2_OUT}
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "rule_set": ["cn-domains", "cn-ip"],
        "outbound": "direct"
      },
      {
        "rule_set": ["private"],
        "outbound": "direct"
      }
    ],
    "final": "hy2-proxy",
    "rule_set": [
      {
        "tag": "cn-domains",
        "type": "local",
        "format": "binary",
        "path": "/etc/sing-box/rule-set/cn-domains.srs"
      },
      {
        "tag": "cn-ip",
        "type": "local",
        "format": "binary",
        "path": "/etc/sing-box/rule-set/cn-ip.srs"
      },
      {
        "tag": "private",
        "type": "local",
        "format": "binary",
        "path": "/etc/sing-box/rule-set/private.srs"
      }
    ]
  }
}
JSONEOF

echo "--- sing-box config ---"
cat /etc/sing-box/config.json
echo "-----------------------"

exec sing-box run -c /etc/sing-box/config.json
