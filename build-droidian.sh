#!/bin/bash

set -euo pipefail

abort() {
    cd -
    echo "-----------------------------------------------"
    echo "Kernel compilation failed! Exiting..."
    echo "-----------------------------------------------"
    exit 1
}

usage() {
    cat << EOF
Usage: $(basename "$0") [options]
Options:
    -m, --model [value]    Specify the model code of the phone (e.g. z3s)
    -k, --ksu [y/N]        Include KernelSU
    -r, --recovery [y/N]   Compile kernel for Android Recovery
    -d, --dtbs [y/N]       Compile only DTBs
EOF
}

MODEL=""
KSU_OPTION=""
RECOVERY_OPTION=""
DTB_OPTION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model|-m)
            MODEL="$2"
            shift 2
            ;;
        --ksu|-k)
            KSU_OPTION="$2"
            shift 2
            ;;
        --recovery|-r)
            RECOVERY_OPTION="$2"
            shift 2
            ;;
        --dtbs|-d)
            DTB_OPTION="$2"
            shift 2
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$MODEL" ]]; then
    echo "Model code must be specified."
    usage
    exit 1
fi

echo "Preparing the build environment..."

pushd "$(dirname "$0")" > /dev/null
CORES=$(nproc)

# ---- Toolchain Setup ----
CLANG_VERSION="r450784d"
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-13.0.0_r13/clang-${CLANG_VERSION}.tar.gz"
CLANG_DIR="$PWD/toolchain/clang_14"
CLANG_BIN="$CLANG_DIR/bin"

if [ ! -f "$CLANG_BIN/clang-14" ]; then
    echo "-----------------------------------------------"
    echo "Toolchain not found! Downloading Clang $CLANG_VERSION..."
    echo "-----------------------------------------------"
    rm -rf "$CLANG_DIR"
    mkdir -p "$CLANG_DIR"
    pushd "$CLANG_DIR" > /dev/null
    curl -LJO "$CLANG_URL"
    tar xf "clang-${CLANG_VERSION}.tar.gz"
    rm "clang-${CLANG_VERSION}.tar.gz"
    popd > /dev/null
fi

export PATH="$CLANG_BIN:$PATH"
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
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

MAKE_ARGS="LLVM=1 LLVM_IAS=1 ARCH=arm64 O=out"

# ---- Model/Board Handling ----
case $MODEL in
z3s)
    BOARD=SRPSI19B018KU
    DEFCONFIG=z3s_defconfig
    ;;
# Add other models as needed
*)
    echo "Unsupported model: $MODEL"
    usage
    exit 1
esac

# ---- Unified CMDLINE ----
UNIFIED_CMDLINE="console=tty0 androidboot.selinux=permissive lxc.enable=1 droidian.lvm.prefer=1 androidboot.hardware=exynos990 loop.max_part=7"

# ---- Droidian/Halium full config written once ----
cat > arch/arm64/configs/z3s.config <<EOF
# z3s.config - comprehensive Droidian kernel config
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=m
CONFIG_ANDROID_BINDER_IPC_SELFTEST=y
CONFIG_ANDROID_PARANOID_NETWORK=n
CONFIG_ANDROID_RAM_CONSOLE=y
CONFIG_ANDROID_VIRT_DRIVERS=y
CONFIG_ANDROID_BOOT_PARAM=y
CONFIG_ANDROID_LOGGER=y
CONFIG_ANDROID_LOW_MEMORY_KILLER=y
CONFIG_F2FS_FS=y
CONFIG_F2FS_FS_XATTR=y
CONFIG_UBIFS_FS=y
CONFIG_EXT4_FS=y
CONFIG_EXFAT_FS=y
CONFIG_ZRAM=y
CONFIG_SECURITY=y
CONFIG_SECURITY_SELINUX=y
CONFIG_SECURITY_APPARMOR=m
CONFIG_SECURITY_LOCKDOWN_LSM=y
CONFIG_KEYS=y
CONFIG_KEYS_COMPAT=y
CONFIG_CRYPTO_USER_API_HASH=y
CONFIG_NAMESPACES=y
CONFIG_CGROUPS=y
CONFIG_CGROUP_CPUACCT=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_SCHED=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_BPF=y
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_NET_NS=y
CONFIG_UTS_NS=y
CONFIG_DEVPTS_MULTIPLE_INSTANCES=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_EXYNOS_VDD_CPU=y
CONFIG_EXYNOS_THERMAL=y
CONFIG_EXYNOS_PM_QOS=y
CONFIG_SAMSUNG_VBMETA_IS_SUPPORTED=y
CONFIG_SEC_ABC=y
CONFIG_SEC_QC_FEATURE=y
CONFIG_NETFILTER=y
CONFIG_NETFILTER_XT_MATCH_STATE=y
CONFIG_NETFILTER_XT_TARGET_MASQUERADE=y
CONFIG_IP_MULTICAST=y
CONFIG_IPV6=y
CONFIG_CPU_FREQ_GOV_ONDEMAND=y
CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y
CONFIG_CPU_IDLE=y
CONFIG_MODULES=y
CONFIG_DYNAMIC_DEBUG=y
CONFIG_DEBUG_INFO=y
CONFIG_DEBUG_KERNEL=y
CONFIG_FTRACE=y
CONFIG_KPROBES=y
CONFIG_TRACEPOINTS=y
CONFIG_DEBUG_FS=y
CONFIG_PROC_FS=y
CONFIG_KALLSYMS=y
CONFIG_CONSOLE_POLL=y
CONFIG_DEBUG_BUGVERBOSE=y
CONFIG_MEDIA_SUPPORT=y
CONFIG_USB_SUPPORT=y
CONFIG_CMDLINE="$UNIFIED_CMDLINE"
EOF

KSU=""
RECOVERY=""
DTBS=""

if [[ "$RECOVERY_OPTION" == "y" ]]; then
    RECOVERY=recovery.config
    KSU_OPTION=n
fi

if [ -z "${KSU_OPTION:-}" ]; then
    read -p "Include KernelSU (y/N): " KSU_OPTION
fi

if [[ "$KSU_OPTION" == "y" ]]; then
    KSU=ksu.config
fi

if [[ "$DTB_OPTION" == "y" ]]; then
    DTBS=y
fi

rm -rf build/out/$MODEL
mkdir -p build/out/$MODEL/zip/files
mkdir -p build/out/$MODEL/zip/META-INF/com/google/android

# ---- Kernel Build ----
echo "-----------------------------------------------"
echo "Defconfig: $DEFCONFIG"
echo "KSU: ${KSU:-N}"
echo "Recovery: ${RECOVERY:+Y}"
echo "-----------------------------------------------"
echo "Generating and merging configuration file..."
make ${MAKE_ARGS} -j$CORES $DEFCONFIG z3s.config $KSU $RECOVERY || abort

if [ ! -z "$DTBS" ]; then
    MAKE_ARGS="$MAKE_ARGS dtbs"
    echo "Building DTBs only..."
else
    echo "Building kernel..."
fi

echo "-----------------------------------------------"
make ${MAKE_ARGS} -j$CORES || abort

# ---- Packaging ----
DTB_PATH=build/out/$MODEL/dtb.img
KERNEL_PATH=build/out/$MODEL/Image
BASE=0x10000000
KERNEL_OFFSET=0x00008000
DTB_OFFSET=0x00000000
RAMDISK_OFFSET=0x01000000
SECOND_OFFSET=0xF0000000
TAGS_OFFSET=0x00000100
HASHTYPE=sha1
HEADER_VERSION=2
CMDLINE="$UNIFIED_CMDLINE"
OS_PATCH_LEVEL=2025-03
OS_VERSION=15.0.0
PAGESIZE=2048
RAMDISK=build/out/$MODEL/ramdisk.cpio.gz
OUTPUT_FILE=build/out/$MODEL/boot.img

if [ -z "$DTBS" ]; then
    cp out/arch/arm64/boot/Image build/out/$MODEL
fi

echo "Building exynos9830 Device Tree Blob Image..."
./toolchain/mkdtimg cfg_create build/out/$MODEL/dtb.img build/dtconfigs/exynos9830.cfg -d out/arch/arm64/boot/dts/exynos

echo "Building Device Tree Blob Output Image for $MODEL..."
./toolchain/mkdtimg cfg_create build/out/$MODEL/dtbo.img build/dtconfigs/$MODEL.cfg -d out/arch/arm64/boot/dts/samsung

if [ -z "$RECOVERY" ] && [ -z "$DTBS" ]; then
    echo "Building RAMDisk..."
    pushd build/ramdisk > /dev/null
    find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../out/$MODEL/ramdisk.cpio.gz || abort
    popd > /dev/null

    echo "Creating boot image..."
    ./toolchain/mkbootimg --base $BASE --board $BOARD --cmdline "$UNIFIED_CMDLINE" --dtb $DTB_PATH \
        --dtb_offset $DTB_OFFSET --hashtype $HASHTYPE --header_version $HEADER_VERSION --kernel $KERNEL_PATH \
        --kernel_offset $KERNEL_OFFSET --os_patch_level $OS_PATCH_LEVEL --os_version $OS_VERSION --pagesize $PAGESIZE \
        --ramdisk $RAMDISK --ramdisk_offset $RAMDISK_OFFSET \
        --second_offset $SECOND_OFFSET --tags_offset $TAGS_OFFSET -o $OUTPUT_FILE || abort

    echo "Building zip package..."
    cp build/out/$MODEL/boot.img build/out/$MODEL/zip/files/boot.img
    cp build/out/$MODEL/dtbo.img build/out/$MODEL/zip/files/dtbo.img
    cp build/update-binary build/out/$MODEL/zip/META-INF/com/google/android/update-binary
    cp build/updater-script build/out/$MODEL/zip/META-INF/com/google/android/updater-script

    version=$(grep -o 'CONFIG_LOCALVERSION="[^"]*"' arch/arm64/configs/exynos9830_defconfig | cut -d '"' -f 2)
    version=${version:1}
    pushd build/out/$MODEL/zip > /dev/null
    DATE=$(date +"%d-%m-%Y_%H-%M-%S")
    if [[ "$KSU_OPTION" == "y" ]]; then
        NAME="${version}_${MODEL}_UNOFFICIAL_KSU_${DATE}.zip"
    else
        NAME="${version}_${MODEL}_UNOFFICIAL_${DATE}.zip"
    fi
    zip -r -qq ../"$NAME" .
    popd > /dev/null
fi

popd > /dev/null
echo "Build finished successfully!"
