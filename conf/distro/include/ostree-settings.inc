# Define OSTree sample keys directory
OSTREE_SAMPLE_KEYS_DIR ?= "${LAYER_PATH_lat-layer}/conf/distro/files/ostree-sample-keys"
OSTREE_KEYS_DIR ?= "${OSTREE_SAMPLE_KEYS_DIR}"

OSTREE_INITRAMFS_IMAGE ?= "initramfs-ostree-image"
OSTREE_REPO ?= "${DEPLOY_DIR_IMAGE}/ostree_repo"

OSTREE_BRANCHNAME ?= "${IMAGE_BASENAME}"
OSTREE_OSNAME ?= "lat_os"
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

OSTREE_USE_AB ??= "1"
OSTREE_REMOTE_NAME ??= "${OSTREE_OSNAME}"
OSTREE_REMOTE_URL ??= ""

# WIC wks configuration variables follow
# The selection of the wks file is:
#   Bootloader - ab/noab

OSTREE_ARCH_WKS_x86 ??= "ostree-grub"
OSTREE_ARCH_WKS_x86-64 ??= "ostree-grub"

OSTREE_ARCH_WKS_arm ??= "ostree-uboot-sd"
OSTREE_ARCH_WKS_armv7 ??= "ostree-uboot-sd"
OSTREE_ARCH_WKS_armv7ve ??= "ostree-uboot-sd"
OSTREE_ARCH_WKS_aarch64 ??= "ostree-uboot-sd"

OSTREE_AB_WKS ??= "${@oe.utils.conditional('OSTREE_USE_AB', '1', '-ab', '-noab', d)}"

# Set a fixed size in the wks file for the various partitions from local.conf e.g.
#OSTREE_WKS_EFI_SIZE = "--size=32M --overhead-factor 1"
#OSTREE_WKS_BOOT_SIZE = "--size=300M --overhead-factor 1"
#OSTREE_WKS_ROOT_SIZE = "--size=1024M --overhead-factor 1"
#OSTREE_WKS_FLUX_SIZE = "--size=1024M --overhead-factor 1"

def get_fluxdata_size(d):
    import subprocess

    overhead_factor = float(d.getVar("IMAGE_OVERHEAD_FACTOR"))
    fluxdata_dir = d.expand("${WORKDIR}/rootfs_ota_var")
    output = subprocess.check_output(["du", "-ks", fluxdata_dir])
    size_kb = int(output.split()[0])
    base_size = size_kb * overhead_factor
    bb.debug(1, '%f = %d * %f' % (base_size, size_kb, overhead_factor))

    if base_size != int(base_size):
        base_size = int(base_size + 1)
    else:
        base_size = int(base_size)

    # Extra 512MB for /var
    base_size += 512*1024
    bb.debug(1, 'returning %d' % (base_size))
    return base_size

python do_write_wks_template_prepend () {
    fluxdata_dir = d.expand("${WORKDIR}/rootfs_ota_var")
    if os.path.exists(fluxdata_dir):
        template_body = d.getVar('_WKS_TEMPLATE')

        root_size = d.getVar("OSTREE_WKS_ROOT_SIZE") or None
        if root_size is None:
            # KB --> MB
            _size = get_rootfs_size(d)//1024 + 1
            root_size = "--size=%dM --overhead-factor 1" % _size
        template_body = template_body.replace("@OSTREE_WKS_ROOT_SIZE@", str(root_size))

        fluxdata_size = d.getVar("OSTREE_WKS_FLUX_SIZE") or None
        if fluxdata_size is None:
            # KB --> MB
            _size = get_fluxdata_size(d)//1024 + 1
            fluxdata_size = "--size=%dM --overhead-factor 1" % _size
        template_body = template_body.replace("@OSTREE_WKS_FLUX_SIZE@", str(fluxdata_size))

        d.setVar("_WKS_TEMPLATE", template_body)
        bb.debug(1, "_WKS_TEMPLATE %s" % template_body)
}

python () {
    if d.getVar('USING_WIC'):
        wks_file_u = d.getVar('WKS_FULL_PATH', False)
        wks_file = d.expand(wks_file_u)
        base, ext = os.path.splitext(wks_file)
        if ext == '.in' and os.path.exists(wks_file):
            bb.build.addtask('do_write_wks_template', 'do_image_wic', 'do_image_otaimg', d)
}

OSTREE_WKS_EFI_SIZE ??= "--size=32M"
OSTREE_WKS_BOOT_SIZE ??= ""
OSTREE_WKS_ROOT_SIZE ??= ""
OSTREE_WKS_FLUX_SIZE ??= ""

# Parition type for /var
OSTREE_FLUX_PART ??= "${@bb.utils.contains('DISTRO_FEATURES', 'luks', 'luksfluxdata', 'fluxdata',d)}"

# Name of the boot loader to include in the file system
OSTREE_BOOTLOADER_x86 ??= 'grub'
OSTREE_BOOTLOADER_x86-64 ??= 'grub'
OSTREE_BOOTLOADER_arm ??= 'u-boot'
OSTREE_BOOTLOADER_armv7 ??= 'u-boot'
OSTREE_BOOTLOADER_armv7ve ??= 'u-boot'
OSTREE_BOOTLOADER_aarch64 ??= 'u-boot'

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
OSTREE_CONSOLE_PRI_arm ??= "console=\${console},\${baudrate}"
OSTREE_CONSOLE_PRI_armv7 ??= "console=\${console},\${baudrate}"
OSTREE_CONSOLE_PRI_armv7ve ??= "console=\${console},\${baudrate}"
OSTREE_CONSOLE_PRI_aarch64 ??= "console=\${console},\${baudrate}"

OSTREE_CONSOLE_AUX ??= "console=ttyS0,115200 "
OSTREE_CONSOLE_AUX_x86 ??= "console=ttyS0,115200 "
OSTREE_CONSOLE_AUX_x86-64 ??= "console=ttyS0,115200 "
OSTREE_CONSOLE_AUX_arm ??= "console=tty0 "
OSTREE_CONSOLE_AUX_armv7 ??= "console=tty0 "
OSTREE_CONSOLE_AUX_armv7ve ??= "console=tty0 "
OSTREE_CONSOLE_AUX_aarch64 ??= "console=tty0 "

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
