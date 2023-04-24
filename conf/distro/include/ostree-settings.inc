# Define OSTree sample keys directory
OSTREE_SAMPLE_KEYS_DIR ?= "${LAYER_PATH_lat-layer}/conf/distro/files/ostree-sample-keys"
OSTREE_KEYS_DIR ?= "${OSTREE_SAMPLE_KEYS_DIR}"

OSTREE_INITRAMFS_IMAGE ?= "initramfs-ostree-image"
OSTREE_REPO ??= "${DEPLOY_DIR_IMAGE}/ostree_repo"

OSTREE_BRANCHNAME ??= "${IMAGE_BASENAME}"
OSTREE_OSNAME ??= "lat_os"
# This is set to the name of the loader to include into a disk image
# Not all BSPs will need this, so it can be unset by the BSP
OSTREE_BOOTLOADER_INCLUDE ??= "${OSTREE_BOOTLOADER}"
OSTREE_KERNEL_ARGS ??= "ro rootwait"

# The OSTREE_SKIP_BOOT_DIFF can be one of the following:
#   0 = Perform a full fsck and boot diff
#   1 = Skip the FSCK check
#   2 = Skip the FSCK and the boot
OSTREE_SKIP_BOOT_DIFF ??= "2"

OSTREE_GPGID ??= "OSTree-Sample-Key"
OSTREE_GPG_PASSPHRASE ??= "ostree"
OSTREE_GPGDIR ??= "${OSTREE_KEYS_DIR}/rpm_keys"

# Generate rootfs.ostree.tar.bz2 files which could be used to build a new repo
# OSTREE_CREATE_TARBALL = "1"

# Configuration of image upgrade and install variables

OSTREE_USE_AB ??= "0"
OSTREE_REMOTE_NAME ??= "${OSTREE_OSNAME}"
OSTREE_REMOTE_URL ??= ""

# WIC wks configuration variables follow
# The selection of the wks file is:
#   Bootloader - ab/noab

OSTREE_ARCH_WKS:x86 ??= "ostree-grub"
OSTREE_ARCH_WKS:x86-64 ??= "ostree-grub"

OSTREE_ARCH_WKS:arm ??= "ostree-uboot-sd"
OSTREE_ARCH_WKS:armv7 ??= "ostree-uboot-sd"
OSTREE_ARCH_WKS:armv7ve ??= "ostree-uboot-sd"
OSTREE_ARCH_WKS:aarch64 ??= "ostree-uboot-sd"

OSTREE_AB_WKS ??= "${@oe.utils.conditional('OSTREE_USE_AB', '1', '-ab', '-noab', d)}"

OSTREE_USE_FIT ??= "0"

# Set a fixed size in the wks file for the various partitions from local.conf e.g.
#OSTREE_WKS_EFI_SIZE = "--size=32M --overhead-factor 1"
#OSTREE_WKS_BOOT_SIZE = "--size=300M --overhead-factor 1"
#OSTREE_WKS_ROOT_SIZE = "--size=1024M --overhead-factor 1"
#OSTREE_WKS_FLUX_SIZE = "--size=1024M --overhead-factor 1"

OSTREE_WKS_EFI_SIZE ??= "--size=32M"
OSTREE_WKS_BOOT_SIZE ??= ""
OSTREE_WKS_ROOT_SIZE ??= ""
OSTREE_WKS_FLUX_SIZE ??= ""

# Parition type for /var
OSTREE_FLUX_PART ??= "${@bb.utils.contains('DISTRO_FEATURES', 'luks', 'luksfluxdata', 'fluxdata',d)}"

# Name of the boot loader to include in the file system
OSTREE_BOOTLOADER:x86 ??= 'grub'
OSTREE_BOOTLOADER:x86-64 ??= 'grub'
OSTREE_BOOTLOADER:arm ??= 'u-boot'
OSTREE_BOOTLOADER:armv7 ??= 'u-boot'
OSTREE_BOOTLOADER:armv7ve ??= 'u-boot'
OSTREE_BOOTLOADER:aarch64 ??= 'u-boot'

# Define any special partitions required where loaders, firmware etc
# live It is intended that these are defined by the BSP as needed
OSTREE_SD_UBOOT_WIC1 ??= "part / --source rawcopy --sourceparams="file=${UBOOT_BINARY}" --ondisk mmcblk --no-table --align 1 --size 1"
OSTREE_SD_UBOOT_WIC2 ??= ""
OSTREE_SD_UBOOT_WIC3 ??= ""
OSTREE_SD_UBOOT_WIC4 ??= ""

# The OSTREE_CONSOLE variable will control what kernel command line
# parameters are passed for the console these should be formatted for
# the boot loader specific to the BSP and the OSTREE_CONSOLE_AUX
# should end with a SPACE
OSTREE_CONSOLE_PRI ??= "console=tty1"
OSTREE_CONSOLE_PRI:arm ??= "console=\${console},\${baudrate}"
OSTREE_CONSOLE_PRI:armv7 ??= "console=\${console},\${baudrate}"
OSTREE_CONSOLE_PRI:armv7ve ??= "console=\${console},\${baudrate}"
OSTREE_CONSOLE_PRI:aarch64 ??= "console=\${console},\${baudrate}"

OSTREE_CONSOLE_AUX ??= "console=ttyS0,115200 "
OSTREE_CONSOLE_AUX:x86 ??= "console=ttyS0,115200 "
OSTREE_CONSOLE_AUX:x86-64 ??= "console=ttyS0,115200 "
OSTREE_CONSOLE_AUX:arm ??= "console=tty0 "
OSTREE_CONSOLE_AUX:armv7 ??= "console=tty0 "
OSTREE_CONSOLE_AUX:armv7ve ??= "console=tty0 "
OSTREE_CONSOLE_AUX:aarch64 ??= "console=tty0 "

OSTREE_CONSOLE ??= "${OSTREE_CONSOLE_AUX}${OSTREE_CONSOLE_PRI}"

# This is set to the name of the loader to include into a disk image
# Not all BSPs will need this, so it can be unset by the BSP
OSTREE_SD_BOOT_ALIGN ??= "4"

# Copy the IMAGE_BOOT_FILES when generating the ostree boot partition
OSTREE_COPY_IMAGE_BOOT_FILES ??= "0"

# Use this WKS file with wic (WKS_FILE = "${OSTREE_WKS_FILE}" should be set in the feature
# template or local.conf
OSTREE_WKS_FILE ??= "${OSTREE_ARCH_WKS}${OSTREE_AB_WKS}.wks.in"

# Below are additional variables that can be set in local.conf which are the
# defaults for the network installer

# Boot Loader Magic block offset (where the first partition should start in sectors)
# NOTE: The FSZ, BSZ and RSZ are numeric in MB only e.g. OSTREE_FDISK_FSZ = "64"
OSTREE_FDISK_BLM ??= "2506"
# Size of the Fat / EFI partition
OSTREE_FDISK_FSZ ??= "32"
# Size of the Boot partition
OSTREE_FDISK_BSZ ??= "200"
# Size of the Root partition
OSTREE_FDISK_RSZ ??= "1400"
# Size of the /var partition 0 for fill disk
OSTREE_FDISK_VSZ ??= "0"

# Allow the var directory to be erased via the initramfs boot, when
# using "ostree_upgrade.sh -e".  The default is 1, but for very secure
# targets this could be a dangerous operation so it is configurable.
# OSTREE_ALLOW_RM_VAR = "0"

# What uboot command should be used to start the kernel in the boot.scr file
# OSTREE_UBOOT_CMD ??= "bootz"

# Use file system links for the ostree boot mounts (more secure and the default)
#    OSTREE_BOOTSCR ??= "fs_links"
# Or read a uEnv.txt file from the disk which allows kernel args 
# to be controlled via ostree (less secure)
#    OSTREE_BOOTSCR ??= "env_import"

# Allow a BSP to specify extra cmds in the boot.scr if needed
OSTREE_BOOTSCR_PRECMD ??= ""

# Grub settings for ostree
OSTREE_GRUB_USER ??= "root"
# Default password is root found in the file below, which is a generated hash
OSTREE_GRUB_PW_FILE ??= "${OSTREE_KEYS_DIR}/boot_keys/boot_cfg_pw"

OSTREE_SUPPORTED_ARM64_MACHINES ??= " \
    bcm-2xxx-rpi4 \
    xilinx-zynqmp \
    nxp-imx8 \
    marvell-cn96xx \
    nxp-s32g \
    intel-socfpga-64 \
    ti-j72xx \
    aptiv_cvc_sousa \
    axxiaarm64 \
    nxp-ls1043 \
    nxp-lx2xxx \
"

OSTREE_SUPPORTED_ARM32_MACHINES ??= " \
    xilinx-zynq \
    nxp-imx6 \
    nxp-ls1028 \
    axxiaarm \
"

OSTREE_SUPPORTED_ARM_MACHINES ?= " \
    ${OSTREE_SUPPORTED_ARM64_MACHINES} \
    ${OSTREE_SUPPORTED_ARM32_MACHINES} \
"

OSTREE_KERNEL ??= "${KERNEL_IMAGETYPE}"
RAMDISK_EXT ?= ".${INITRAMFS_FSTYPES}"

BOOTFILES ??= ""

OSTREE_WIFI_PACKAGES ??= ""
OSTREE_WIFI_PACKAGES:intel-x86-64 = " \
    packagegroup-base-wifi \
    linux-firmware-iwlwifi-6000g2a-6 \
    linux-firmware-iwlwifi-6000g2b-6 \
    linux-firmware-iwlwifi-135-6 \
    linux-firmware-iwlwifi-8000c \
    linux-firmware-iwlwifi-8265 \
    linux-firmware-iwlwifi-7265d \
    linux-firmware-iwlwifi-9000 \
    linux-firmware-iwlwifi-misc \
    kernel-module-iwlmvm \
    kernel-module-iwlwifi \
"
