# syntax=docker/dockerfile:1.4

FROM debian:bookworm-slim AS downloader

# BuildKit will set these when using `docker buildx build`
ARG TARGETARCH
ARG TARGETVARIANT

# vcontrold version and deb revision as build args
ARG VCONTROLD_VERSION=0.98.12
ARG VCONTROLD_DEB_REVISION=16

# Only install wget for downloading
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Download the right vcontrold .deb for this architecture
RUN set -eux; \
    case "${TARGETARCH}${TARGETVARIANT:+-${TARGETVARIANT}}" in \
    "amd64") DEB_ARCH="amd64" ;; \
    "arm64") DEB_ARCH="arm64" ;; \
    "arm-v7") DEB_ARCH="armhf" ;; \
    *) echo "Unsupported arch: ${TARGETARCH}${TARGETVARIANT:+-${TARGETVARIANT}}"; exit 1 ;; \
    esac; \
    wget -O /vcontrold.deb \
    "https://github.com/openv/vcontrold/releases/download/v${VCONTROLD_VERSION}/vcontrold_${VCONTROLD_VERSION}-${VCONTROLD_DEB_REVISION}_${DEB_ARCH}.deb"

# Final stage
FROM debian:bookworm-slim

# Copy the downloaded .deb from the previous stage
COPY --from=downloader /vcontrold.deb /tmp/vcontrold.deb

# Install runtime dependencies and vcontrold in a single layer
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    libxml2 \
    mosquitto-clients \
    jq \
    && dpkg -i /tmp/vcontrold.deb \
    && rm /tmp/vcontrold.deb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create required folders and non-root user
RUN groupadd -r vcontrold \
    && useradd --no-log-init -r -g vcontrold -G dialout vcontrold \
    && mkdir -p /config /app \
    && chown -R vcontrold:vcontrold /config

# Copy application files with proper permissions
COPY --chown=vcontrold:vcontrold --chmod=555 ./app /app

USER vcontrold

VOLUME ["/config"]

CMD ["bash", "/app/startup.sh"]
