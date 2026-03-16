# ============================================================
# 1. Ubuntu 18.04 amd64 sysroot (GCC 7 native)
# ============================================================
sudo rm -rf bionic-sysroot
sudo debootstrap --arch=amd64 --variant=minbase \
  --include=libc6-dev,linux-libc-dev,libstdc++-7-dev,gcc-7,g++-7,binutils,libisl19,libmpfr6,libmpc3,libgmp10,zlib1g \
  bionic bionic-sysroot http://archive.ubuntu.com/ubuntu

sudo mkdir -p bionic-sysroot/usr/lib/gcc-deps
for lib in libisl.so.19 libmpfr.so.6 libmpc.so.3 libgmp.so.10 libopcodes-2.30-system.so libbfd-2.30-system.so; do
  sudo cp -a "bionic-sysroot/usr/lib/x86_64-linux-gnu/${lib}"* bionic-sysroot/usr/lib/gcc-deps/ 2>/dev/null || echo "WARN: ${lib} not found"
done

sudo tar czf ubuntu-18.04-amd64-sysroot.tar.gz -C bionic-sysroot .
sha256sum ubuntu-18.04-amd64-sysroot.tar.gz

# ============================================================
# 2. Ubuntu 22.04 arm64 sysroot (headers + libs only)
#    Requires: sudo apt install qemu-user-static binfmt-support
# ============================================================
sudo rm -rf jammy-arm64-sysroot
sudo debootstrap --arch=arm64 --variant=minbase \
  --include=libc6-dev,linux-libc-dev,libstdc++-11-dev,g++-11 \
  jammy jammy-arm64-sysroot http://ports.ubuntu.com/ubuntu-ports

sudo tar czf ubuntu-22.04-arm64-sysroot.tar.gz -C jammy-arm64-sysroot .
sha256sum ubuntu-22.04-arm64-sysroot.tar.gz

# ============================================================
# 3. Ubuntu 22.04 arm64 cross-toolchain (amd64 binaries targeting arm64)
# ============================================================
sudo rm -rf cross-arm64-toolchain
sudo debootstrap --arch=amd64 --variant=minbase \
  --include=gcc-11-aarch64-linux-gnu,g++-11-aarch64-linux-gnu,binutils-aarch64-linux-gnu,libisl23,libmpfr6,libmpc3,libgmp10,zlib1g \
  jammy cross-arm64-toolchain http://archive.ubuntu.com/ubuntu

sudo mkdir -p cross-arm64-toolchain/usr/lib/gcc-deps
# Grab ALL shared libs that GCC/binutils tools might need
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

sudo tar czf ubuntu-22.04-arm64-cross-toolchain.tar.gz -C cross-arm64-toolchain .
sha256sum ubuntu-22.04-arm64-cross-toolchain.tar.gz

# ============================================================
# Upload all three
# ============================================================
gh release upload sysroots-v1 \
  ubuntu-18.04-amd64-sysroot.tar.gz \
  ubuntu-22.04-arm64-sysroot.tar.gz \
  ubuntu-22.04-arm64-cross-toolchain.tar.gz \
  --clobber --repo dunv/sysroots
