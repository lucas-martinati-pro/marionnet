# Compile on the oldest Ubuntu host supported by the GitHub releases.
# The UML executable uses the HOST's libc, not the guest filesystem's libc.
FROM ubuntu:22.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      gcc-12 gcc-12-multilib make flex bison libssl-dev libelf-dev bc \
      xz-utils ca-certificates curl file binutils python3 \
 && rm -rf /var/lib/apt/lists/*
# gcc-multilib also installs the /usr/include/asm link used by UML host headers.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gcc-multilib \
 && rm -rf /var/lib/apt/lists/*
