# Shared inputs for the GitHub installer and package builders.
# Source this file; it deliberately does not change shell options or directories.
GITHUB_REPO="${MARIONNET_REPO:-lucas-martinati-pro/marionnet}"
BASE_RELEASE_TAG="v1.0.456"
KERNEL_VER="6.12.95"
KERNEL_I386_REVISION="1"
KERNEL_I386_NAME="linux-${KERNEL_VER}-i386"
FS_VER="18474"
WHEEZY_VERSION="08367"
WHEEZY_IMAGE="machine-debian-wheezy-${WHEEZY_VERSION}"
WHEEZY_DEB_DEFAULT="marionnet-fs-debian-wheezy_${WHEEZY_VERSION}_all.deb"
# This immutable guest package is shared by every application release.
WHEEZY_PINNED_SHA256="7972fa3cc8a6c9389c29a8173c574781ac14d07783fbaa4b954c98a71d8653fd"
KERNELS_DEB="marionnet-kernels_${KERNEL_VER}_amd64.deb"
KERNELS_I386_DEB="marionnet-kernels-i386_${KERNEL_VER}-${KERNEL_I386_REVISION}_amd64.deb"
KERNELS_I386_LEGACY_DEB="marionnet-kernels-i386_${KERNEL_VER}_amd64.deb"
FS_DEB="marionnet-fs-guignol_${FS_VER}_all.deb"
