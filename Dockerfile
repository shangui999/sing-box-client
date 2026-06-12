FROM alpine:latest

ARG SINGBOX_VERSION=1.13.13
ARG RULE_SET_REPO=https://github.com/DustinWin/ruleset_geodata/releases/download/sing-box-rule-set

RUN apk add --no-cache ca-certificates curl && \
    curl -fSL "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-amd64.tar.gz" \
      -o /tmp/sing-box.tar.gz && \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp && \
    mv /tmp/sing-box-${SINGBOX_VERSION}-linux-amd64/sing-box /usr/local/bin/sing-box && \
    chmod +x /usr/local/bin/sing-box && \
    mkdir -p /etc/sing-box/rule-set && \
    # Download built-in rule-sets (CN direct + proxy)
    curl -fSL "${RULE_SET_REPO}/cn-domains.srs" -o /etc/sing-box/rule-set/cn-domains.srs && \
    curl -fSL "${RULE_SET_REPO}/cn-ip.srs" -o /etc/sing-box/rule-set/cn-ip.srs && \
    curl -fSL "${RULE_SET_REPO}/private.srs" -o /etc/sing-box/rule-set/private.srs && \
    curl -fSL "${RULE_SET_REPO}/proxy-domains.srs" -o /etc/sing-box/rule-set/proxy-domains.srs && \
    curl -fSL "${RULE_SET_REPO}/proxy-ip.srs" -o /etc/sing-box/rule-set/proxy-ip.srs && \
    rm -rf /tmp/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
