#!/usr/bin/env bash
# Rebuilds all three sysroot/cross-toolchain tarballs and uploads them as a
# GitHub release.
#
# Required commands: debootstrap, gh, sudo, tar, sha256sum
# Required kernel feature: binfmt_misc registration for aarch64-linux
#   - NixOS:  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
#   - Debian: sudo apt install qemu-user-static binfmt-support
#
# Usage on NixOS:
#   nix shell nixpkgs#debootstrap nixpkgs#gh
#   sudo -E env "PATH=$PATH" bash build.sh
#
# Usage on Debian/distrobox:
#   sudo apt install -y debootstrap qemu-user-static binfmt-support gh
#   sudo bash build.sh
#
# Override the release tag (default: sysroots-v2) or skip upload:
#   RELEASE_TAG=sysroots-v3 sudo -E bash build.sh
#   SKIP_UPLOAD=1            sudo -E bash build.sh

set -euo pipefail

cd "$(dirname "$0")"

# If not root, re-exec under sudo while preserving PATH so the dev-shell
# binaries (debootstrap, gh) remain visible. With this, plain `./build.sh`
# works from a direnv-activated shell — no need to remember
# `sudo -E env "PATH=$PATH" bash build.sh`.
if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E env "PATH=$PATH" bash "$0" "$@"
fi

RELEASE_TAG="${RELEASE_TAG:-sysroots-v2}"
RELEASE_REPO="${RELEASE_REPO:-dunv/sysroots}"
SKIP_UPLOAD="${SKIP_UPLOAD:-0}"

# Resolve absolute paths so `sudo` finds them when its secure_path drops the
# nix-shell PATH. Fail fast with a usable hint if missing.
need() {
  local p
  p=$(command -v "$1") || { echo "error: '$1' not found. ${2:-}" >&2; exit 1; }
  echo "$p"
}
DEBOOTSTRAP=$(need debootstrap "On NixOS: nix shell nixpkgs#debootstrap")
GH=$(need gh "On NixOS: nix shell nixpkgs#gh")
TAR=$(need tar)

# Verify aarch64 binfmt is registered (required for arm64 sysroot second-stage).
# NixOS registers as "aarch64-linux"; Debian/qemu-user-static as "qemu-aarch64".
if [ ! -e /proc/sys/fs/binfmt_misc/aarch64-linux ] \
   && [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
  echo "error: aarch64 binfmt_misc not registered." >&2
  echo "  NixOS:  add 'boot.binfmt.emulatedSystems = [ \"aarch64-linux\" ];' to your config." >&2
  echo "  Debian: sudo apt install qemu-user-static binfmt-support" >&2
  exit 1
fi

# Common dev libraries needed for cross-compiling flutter-pi (KMS/DRM/EGL/GBM
# direct-rendering Flutter embedder). Added to both target sysroots.
FLUTTER_PI_DEPS=(
  libdrm-dev
  libegl1-mesa-dev
  libgbm-dev
  libgles2-mesa-dev
  libinput-dev
  libxkbcommon-dev
  libsystemd-dev
  libudev-dev
  pkg-config
)
flutter_pi_csv="$(IFS=, ; echo "${FLUTTER_PI_DEPS[*]}")"

banner() { printf '\n========== %s ==========\n' "$*"; }

# debootstrap's second-stage may bind-mount /dev, /dev/pts, /proc, /sys etc.
# inside the target. If it crashed, those mounts linger and `rm -rf` fails
# with "Device or resource busy". Lazy-unmount everything under the target
# before deleting it. Safe no-op if there are no mounts.
clean_target() {
  local target="$1"
  [ -e "$target" ] || return 0
  local abs
  abs="$(realpath -s "$target")"
  mount | awk -v t="$abs" '$3 == t || index($3, t"/") == 1 { print $3 }' \
    | sort -r | xargs -r sudo umount -l
  sudo rm -rf "$target"
}

# ------------------------------------------------------------------
# 1. Ubuntu 18.04 amd64 sysroot (GCC 7 native + flutter-pi headers)
# ------------------------------------------------------------------
banner "1/3  Ubuntu 18.04 amd64 sysroot"
clean_target bionic-sysroot
sudo "$DEBOOTSTRAP" --arch=amd64 --variant=minbase \
  --include="libc6-dev,linux-libc-dev,libstdc++-7-dev,gcc-7,g++-7,binutils,libisl19,libmpfr6,libmpc3,libgmp10,zlib1g,${flutter_pi_csv}" \
  bionic bionic-sysroot http://archive.ubuntu.com/ubuntu

sudo mkdir -p bionic-sysroot/usr/lib/gcc-deps
for lib in libisl.so.19 libmpfr.so.6 libmpc.so.3 libgmp.so.10 libopcodes-2.30-system.so libbfd-2.30-system.so; do
  sudo cp -a "bionic-sysroot/usr/lib/x86_64-linux-gnu/${lib}"* bionic-sysroot/usr/lib/gcc-deps/ 2>/dev/null || echo "WARN: ${lib} not found"
done

sudo "$TAR" czf ubuntu-18.04-amd64-sysroot.tar.gz -C bionic-sysroot .

# ------------------------------------------------------------------
# 2. Ubuntu 22.04 arm64 sysroot (headers + libs + flutter-pi deps)
#
# Pre-bind-mount /nix into the target so the qemu-aarch64-binfmt-P wrapper
# (registered by NixOS) can resolve its target binary at
# /nix/store/...-qemu-user-*/bin/qemu-aarch64 during the chroot probe.
# Without /nix accessible inside the chroot, the wrapper fails with ENOENT
# and debootstrap aborts before the second-stage probe.
# ------------------------------------------------------------------
banner "2/3  Ubuntu 22.04 arm64 sysroot"
clean_target jammy-arm64-sysroot

sudo mkdir -p jammy-arm64-sysroot/nix
sudo mount --bind /nix jammy-arm64-sysroot/nix

sudo "$DEBOOTSTRAP" --arch=arm64 --variant=minbase \
  --include="libc6-dev,linux-libc-dev,libstdc++-11-dev,g++-11,${flutter_pi_csv}" \
  jammy jammy-arm64-sysroot http://ports.ubuntu.com/ubuntu-ports

# Tear down the bind mount before tarballing so /nix isn't captured.
sudo umount jammy-arm64-sysroot/nix
sudo rmdir  jammy-arm64-sysroot/nix 2>/dev/null || true

sudo "$TAR" czf ubuntu-22.04-arm64-sysroot.tar.gz -C jammy-arm64-sysroot .

# ------------------------------------------------------------------
# 3. Ubuntu 22.04 arm64 cross-toolchain (amd64 binaries targeting arm64)
# ------------------------------------------------------------------
banner "3/3  Ubuntu 22.04 arm64 cross-toolchain"
clean_target cross-arm64-toolchain
sudo "$DEBOOTSTRAP" --arch=amd64 --variant=minbase \
  --include=gcc-11-aarch64-linux-gnu,g++-11-aarch64-linux-gnu,binutils-aarch64-linux-gnu,libisl23,libmpfr6,libmpc3,libgmp10,zlib1g \
  jammy cross-arm64-toolchain http://archive.ubuntu.com/ubuntu

sudo mkdir -p cross-arm64-toolchain/usr/lib/gcc-deps
for lib in \
  libisl.so.23 \
  libmpfr.so.6 \
  libmpc.so.3 \
  libgmp.so.10 \
  libopcodes-2.38-arm64.so \
  libbfd-2.38-arm64.so \
  libctf-arm64.so.0 \
  libctf-nobfd-arm64.so.0 \
; do
  sudo cp -a "cross-arm64-toolchain/usr/lib/x86_64-linux-gnu/${lib}"* cross-arm64-toolchain/usr/lib/gcc-deps/ 2>/dev/null || echo "WARN: ${lib} not found"
done

sudo "$TAR" czf ubuntu-22.04-arm64-cross-toolchain.tar.gz -C cross-arm64-toolchain .

# ------------------------------------------------------------------
# Hashes
# ------------------------------------------------------------------
banner "sha256sums"
sha256sum \
  ubuntu-18.04-amd64-sysroot.tar.gz \
  ubuntu-22.04-arm64-sysroot.tar.gz \
  ubuntu-22.04-arm64-cross-toolchain.tar.gz

# ------------------------------------------------------------------
# Upload to GitHub release
# ------------------------------------------------------------------
if [ "$SKIP_UPLOAD" = "1" ]; then
  banner "Skipping upload (SKIP_UPLOAD=1)"
  exit 0
fi

banner "Uploading to ${RELEASE_REPO} @ ${RELEASE_TAG}"

# gh stores credentials under $HOME/.config/gh — root has none. Drop back
# to the invoking user (set automatically by sudo as $SUDO_USER) so gh
# uses the same auth context the user has interactively.
gh_user() { sudo -u "${SUDO_USER:-$(logname)}" "$GH" "$@"; }

# Create the release if it doesn't exist; ignore failure if it already does.
gh_user release create "$RELEASE_TAG" \
  --repo "$RELEASE_REPO" \
  --title "$RELEASE_TAG" \
  --notes "Sysroots and arm64 cross-toolchain. Includes flutter-pi cross-build deps (libdrm/EGL/GBM/GLES2/libinput/libxkbcommon/libsystemd/libudev + pkg-config) in both target sysroots." \
  2>/dev/null || true

gh_user release upload "$RELEASE_TAG" \
  ubuntu-18.04-amd64-sysroot.tar.gz \
  ubuntu-22.04-arm64-sysroot.tar.gz \
  ubuntu-22.04-arm64-cross-toolchain.tar.gz \
  --clobber --repo "$RELEASE_REPO"

banner "Done. Release: https://github.com/${RELEASE_REPO}/releases/tag/${RELEASE_TAG}"
