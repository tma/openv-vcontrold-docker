# syntax=docker/dockerfile:1.4
FROM debian:bookworm-slim

# BuildKit will set these when using `docker buildx build`
ARG TARGETARCH
ARG TARGETVARIANT

# vcontrold version and deb revision as build args
ARG VCONTROLD_VERSION=0.98.12
ARG VCONTROLD_DEB_REVISION=16

WORKDIR /tmp

# install tools and runtime dependencies
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        wget \
        libxml2 \
        mosquitto-clients \
        jq && \
    rm -rf /var/lib/apt/lists/*

# download the right vcontrold .deb for this architecture
RUN set -eux; \
    case "${TARGETARCH}${TARGETVARIANT:+-${TARGETVARIANT}}" in \
      "amd64")   DEB_ARCH="amd64" ;; \
      "arm64")   DEB_ARCH="arm64" ;; \
      "arm-v7")  DEB_ARCH="armhf" ;; \
      "arm-v6")  DEB_ARCH="armel" ;; \
      *) echo "Unsupported arch: ${TARGETARCH}${TARGETVARIANT:+-${TARGETVARIANT}}"; exit 1 ;; \
    esac; \
    wget -O /vcontrold.deb \
      "https://github.com/openv/vcontrold/releases/download/v${VCONTROLD_VERSION}/vcontrold_${VCONTROLD_VERSION}-${VCONTROLD_DEB_REVISION}_${DEB_ARCH}.deb"

# install vcontrold, then clean up the .deb
RUN dpkg -i /vcontrold.deb && \
    rm /vcontrold.deb

# create required folders
RUN mkdir /config /app

# copy the required code files
COPY ./app /app
RUN chmod -R 555 /app

# set up non-root user
RUN groupadd -r vcontrold && useradd --no-log-init -r -g vcontrold vcontrold
USER vcontrold

VOLUME ["/config"]

CMD ["bash", "/app/startup.sh"]
