#
# Copyright (C) 2017 Wind River Systems, Inc.
#

MACHINE_FEATURES += "x86 pci usbhost ext2 keyboard screen alsa acpi vfat serial"
MACHINE_FEATURES += "efi pcbios"
MACHINE_FEATURES += "parser shell-tools filesystem profile network"

MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-iwlwifi-6000g2a-6"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-iwlwifi-6000g2b-6"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-iwlwifi-135-6"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-bnx2-mips"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-iwlwifi-8000c"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-iwlwifi-8265"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-radeon"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-pcie8897"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-iwlwifi-7265d"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-i915"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-ibt-12-16"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-rtl8723"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-ibt-17"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-iwlwifi-9000"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-ice"

MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-iwlwifi-misc"
MACHINE_EXTRA_RRECOMMENDS += "linux-firmware-ibt-misc"

EFI_PROVIDER ?= "${@bb.utils.contains('INCOMPATIBLE_LICENSE', 'GPLv3', 'systemd-boot', 'grub-efi', d)}"

# grub-efi is depended in wic.bbclass, remove it to aviod depency error.
WKS_FILE_DEPENDS_BOOTLOADERS_remove = "${@bb.utils.contains('INCOMPATIBLE_LICENSE', 'GPLv3', 'grub-efi', '', d)}"

# Do not include installer routine when GPLv3 is not allowed.
INITRAMFS_SCRIPTS_remove = "${@bb.utils.contains('INCOMPATIBLE_LICENSE', 'GPLv3', 'initramfs-module-install initramfs-module-install-efi', '', d)}"
LABELS_LIVE_remove = "${@bb.utils.contains('INCOMPATIBLE_LICENSE', 'GPLv3', 'install', '', d)}"

KERNEL_IMAGETYPE = "bzImage"

SERIAL_CONSOLES = "115200;ttyS0 115200;ttyUSB0"

MACHINEOVERRIDES_append = ":intel-x86"

XSERVER ?= "xserver-xorg \
	   xserver-xorg-extension-dri \
	   xserver-xorg-extension-dri2 \
	   xserver-xorg-extension-extmod \
	   xserver-xorg-extension-dbe \
	   xserver-xorg-module-libint10 \
	   xf86-input-mouse \
	   xf86-input-keyboard \
	   xf86-input-evdev \
	   xf86-input-synaptics \
	   xf86-video-vesa \
	   xf86-video-fbdev \
	   xf86-video-mga \
	   xf86-video-modesetting \
	   \
	   ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'mesa-driver-swrast xserver-xorg-extension-glx', '', d)} \
	   ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'mesa-driver-i915 mesa-driver-i965', '', d)} \
	   ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'mesa mesa-demos', '', d)} \
	   ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'xf86-video-ati xf86-video-intel', '', d)} \
	   matchbox-wm"

PREFERRED_PROVIDER_libglu = "libglu"
PREFERRED_VERSION_virtual/mesa = "17.1.5"

PREFERRED_PROVIDER_virtual/kernel ??= "linux-yocto"
PREFERRED_VERSION_linux-yocto ?= "5.10%"

TARGET_QEMU_BIN = "qemu-system-x86_64"
TARGET_QEMU_KERNEL="bzImage"
TARGET_QEMU_KERNEL_OPTS="selinux=0 enforcing=0"
TARGET_QEMU_ENET_MODEL="i82557b"
TARGET_QEMU_BOOT_CONSOLE="ttyS0,115200"
TARGET_QEMU_OPTS="-show-cursor -usb -usbdevice wacom-tablet -vga vmware"
TARGET_QEMU_CPU="Nehalem"

IMAGE_FSTYPES += "live wic wic.bmap"

WKS_FILE ?= "${@bb.utils.contains('INCOMPATIBLE_LICENSE', 'GPLv3', 'systemd-bootdisk.wks', 'intel-x86-mkefidisk.wks', d)}"
do_image_wic[depends] += "gptfdisk-native:do_populate_sysroot"
do_image_wic[recrdeptask] += "do_bootimg"

# DPDK enable and configuration
COMPATIBLE_MACHINE_intel-x86_pn-dpdk = "${MACHINE}"
PREFERRED_VERSION_dpdk ?= "19.11.%"
