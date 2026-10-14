ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}
ARG RUNTIME_PACKAGES
RUN test -n "$RUNTIME_PACKAGES" \
 && dpkg --add-architecture i386 \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      dpkg-dev libc6:i386 ca-certificates curl file python3 python3-pexpect \
      $RUNTIME_PACKAGES \
 && rm -rf /var/lib/apt/lists/*
