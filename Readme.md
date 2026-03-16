# Sysroots

## AMD64
```bash
sudo debootstrap --arch=amd64 --variant=minbase \
  --include=libc6-dev,linux-libc-dev,libstdc++-7-dev,gcc-7,g++-7,binutils,libisl19,libmpfr6,libmpc3,libgmp10,zlib1g \
  bionic bionic-sysroot http://archive.ubuntu.com/ubuntu

sudo mkdir -p bionic-sysroot/usr/lib/gcc-deps
for lib in libisl.so.19 libmpfr.so.6 libmpc.so.3 libgmp.so.10; do
  sudo cp -a "bionic-sysroot/usr/lib/x86_64-linux-gnu/${lib}"* bionic-sysroot/usr/lib/gcc-deps/
done

sudo tar czf ubuntu-18.04-amd64-sysroot.tar.gz -C bionic-sysroot .
```

## ARM64
```bash

# sysroot
sudo debootstrap --arch=arm64 --variant=minbase \
  --include=libc6-dev,linux-libc-dev,libstdc++-11-dev,g++-11 \
  jammy jammy-arm64-sysroot http://ports.ubuntu.com/ubuntu-ports

sudo tar czf ubuntu-22.04-arm64-sysroot.tar.gz -C jammy-arm64-sysroot .

# cross-compilation toolchain (amd64 binaries targeting arm64)
sudo debootstrap --arch=amd64 --variant=minbase \
  --include=gcc-11-aarch64-linux-gnu,g++-11-aarch64-linux-gnu,binutils-aarch64-linux-gnu,libisl23,libmpfr6,libmpc3,libgmp10,zlib1g \
  jammy cross-arm64-toolchain http://archive.ubuntu.com/ubuntu
sudo mkdir -p cross-arm64-toolchain/usr/lib/gcc-deps
for lib in libisl.so.23 libmpfr.so.6 libmpc.so.3 libgmp.so.10 libopcodes-2.38-arm64.so libbfd-2.38-arm64.so; do
  sudo cp -a "cross-arm64-toolchain/usr/lib/x86_64-linux-gnu/${lib}"* cross-arm64-toolchain/usr/lib/gcc-deps/
done
sudo tar czf ubuntu-22.04-arm64-cross-toolchain.tar.gz -C cross-arm64-toolchain .
```

# Upload

## Create
```bash
gh release create sysroots-v1 \
  ubuntu-18.04-amd64-sysroot.tar.gz \
  ubuntu-22.04-arm64-sysroot.tar.gz \
  ubuntu-22.04-arm64-cross-toolchain.tar.gz \
  --repo dunv/sysroots \
  --title "Sysroot tarballs v1" \
  --notes "Ubuntu 18.04 amd64 (glibc 2.27) + Ubuntu 22.04 arm64 (glibc 2.35)"
```

## Update
```bash
gh release upload sysroots-v1 \
  ubuntu-18.04-amd64-sysroot.tar.gz \
  ubuntu-22.04-arm64-sysroot.tar.gz \
  ubuntu-22.04-arm64-cross-toolchain.tar.gz \
  --clobber --repo dunv/sysroots
```
