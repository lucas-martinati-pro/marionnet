#!/usr/bin/env bash
# Build the guest kernel against Ubuntu 22.04's libc, never the packager's libc.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/dist/release-components.sh"
VERSION="${1:-$KERNEL_VER}"
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid kernel version' >&2; exit 2; }
OUT="${2:-$ROOT/dist/_build.kernel-i386-release}"
mkdir -p "$OUT" "$ROOT/uml/pupisto.kernel/_build.downloads"
OUT="$(realpath "$OUT")"
TARBALL="$ROOT/uml/pupisto.kernel/_build.downloads/linux-$VERSION.tar.xz"
if [[ ! -s $TARBALL ]]; then
  curl -fL --retry 3 "https://www.kernel.org/pub/linux/kernel/v${VERSION%%.*}.x/linux-$VERSION.tar.xz" -o "$TARBALL.part"
  mv "$TARBALL.part" "$TARBALL"
fi
docker build -f "$ROOT/dist/kernel-i386.Dockerfile" -t marionnet-kernel-i386-builder:jammy "$ROOT/dist"
docker run --rm \
  -v "$TARBALL:/linux.tar.xz:ro" -v "$ROOT/uml/kernel:/configs:ro" -v "$OUT:/out" \
  -e VERSION="$VERSION" -e BUILD_JOBS="${BUILD_JOBS:-4}" \
  -e OUTPUT_OWNER="$(id -u):$(id -g)" \
  marionnet-kernel-i386-builder:jammy bash -euc '
    mkdir /build
    tar -xJf /linux.tar.xz --strip-components=1 -C /build
    cd /build
    if test -f "/configs/CONFIG-$VERSION-i386"; then
      cp "/configs/CONFIG-$VERSION-i386" .config
    else
      make ARCH=um SUBARCH=i386 CC=gcc-12 HOSTCC=gcc-12 defconfig
      scripts/config -e EXT2_FS -e EXT3_FS -e EXT4_FS -e HOSTFS -e BLK_DEV_UBD \
        -e UML_NET -e UML_NET_TUNTAP -e UML_NET_DAEMON
    fi
    scripts/kconfig/merge_config.sh -m .config /configs/CONFIG-i386-netfilter
    make ARCH=um SUBARCH=i386 CC=gcc-12 HOSTCC=gcc-12 olddefconfig
    while IFS= read -r setting; do
      [[ $setting = CONFIG_*=y ]] || continue
      grep -qxF "$setting" .config || { echo "Missing: $setting" >&2; exit 1; }
    done < /configs/CONFIG-i386-netfilter
    make ARCH=um SUBARCH=i386 CC=gcc-12 HOSTCC=gcc-12 -j"$BUILD_JOBS"
    cp linux "/out/linux-$VERSION-i386"
    strip "/out/linux-$VERSION-i386"
    cp .config "/out/linux-$VERSION-i386.config"
    file "/out/linux-$VERSION-i386"
    readelf -V "/out/linux-$VERSION-i386" > /out/glibc-requirements.txt
    # Reject host ABI requirements above the supported Ubuntu 22.04 floor.
    for requirement in $(grep -oE "Name: GLIBC_[0-9.]+" /out/glibc-requirements.txt | cut -d_ -f2); do
      dpkg --compare-versions "$requirement" le 2.35 || {
        echo "Unsupported glibc requirement: $requirement" >&2; exit 1;
      }
    done
    chown -R "$OUTPUT_OWNER" /out
  '
echo "Kernel and config: $OUT"
