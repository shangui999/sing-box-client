FROM alpine:latest

ARG MIHOMO_REPO=https://github.com/MetaCubeX/mihomo/releases/latest/download

RUN apk add --no-cache ca-certificates curl yq && \
    MIHOMO_VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | yq '.tag_name') && \
    curl -fSL "https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/mihomo-linux-amd64-compatible-${MIHOMO_VERSION}.gz" \
      -o /tmp/mihomo.gz && \
    gunzip /tmp/mihomo.gz && \
    mv /tmp/mihomo /usr/local/bin/mihomo && \
    chmod +x /usr/local/bin/mihomo && \
    mkdir -p /etc/mihomo/rules && \
    # Download GeoIP and GeoSite databases
    curl -fSL "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb" \
      -o /etc/mihomo/geoip.metadb && \
    curl -fSL "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat" \
      -o /etc/mihomo/geosite.dat && \
    rm -rf /tmp/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
