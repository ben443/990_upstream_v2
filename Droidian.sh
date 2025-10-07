#!/bin/bash
set -euo pipefail

# Samsung Galaxy S20 Ultra (z3s) Droidian kernel build script - Final version

# Recommended toolchain versions:
# Android NDK: r25b (latest stable as of 2025)
# GCC fallback prefix: aarch64-linux-gnu-10 or newer (if fallback needed)

# Set kernel source root to current directory
KERNEL_ROOT=$(pwd)

# Kernel configs directory
DEFCONFIG_PATH=${KERNEL_ROOT}/arch/arm64/configs

# Device and Droidian config
DEVICE_DEFCONFIG=z3s_defconfig
HALIUM_CONFIG=halium.config
COMBINED_DEFCONFIG=combined_z3s_defconfig

# Output directories
OUT_DIR=${KERNEL_ROOT}/out
INSTALL_MOD_PATH=${OUT_DIR}/modules_install

# Toolchain path - change if your NDK location differs
TOOLCHAIN_PATH=${HOME}/toolchains/android-ndk-r25b/toolchains/llvm/prebuilt/linux-x86_64/bin

# GCC cross-compile prefix if needed
CROSS_COMPILE=aarch64-linux-gnu-

# Export environment for build using Android NDK clang
export PATH=${TOOLCHAIN_PATH}:$PATH
export CC=clang
export CXX=clang++
export LD=ld.lld
export AR=llvm-ar
export AS=clang
export NM=llvm-nm
export STRIP=llvm-strip
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export RANLIB=llvm-ranlib

export CROSS_COMPILE
export ARCH=arm64

# Parallel build jobs - detect automatically
JOBS=$(nproc)

# Functions for logging
log_info() { echo -e "e[1;34m[INFO]e[0m $*"; }
log_error() { echo -e "e[1;31m[ERROR]e[0m $*" >&2; }

log_info "Starting Samsung Galaxy S20 Ultra (z3s) Droidian kernel build..."

log_info "Cleaning previous build artifacts..."
make mrproper

log_info "Applying device defconfig: ${DEVICE_DEFCONFIG}..."
make ${DEVICE_DEFCONFIG}

log_info "Merging halium config: ${HALIUM_CONFIG}..."
cp .config .config.tmp
scripts/kconfig/merge_config.sh -m ${DEFCONFIG_PATH}/${HALIUM_CONFIG} .config.tmp > .config.merged
cp .config.merged .config

log_info "Saving combined defconfig as: ${COMBINED_DEFCONFIG}..."
make savedefconfig
mv defconfig ${DEFCONFIG_PATH}/${COMBINED_DEFCONFIG}

log_info "Starting kernel build with combined defconfig..."
make O=${OUT_DIR} ARCH=arm64 ${COMBINED_DEFCONFIG}
make -j${JOBS} O=${OUT_DIR} ARCH=arm64

log_info "Installing kernel modules..."
make O=${OUT_DIR} ARCH=arm64 INSTALL_MOD_PATH=${INSTALL_MOD_PATH} modules_install

log_info "Kernel build and modules installation complete."
log_info "Kernel Image and device tree binaries located in: ${OUT_DIR}"
log_info "Modules installed to: ${INSTALL_MOD_PATH}"

log_info "Build script finished successfully."
