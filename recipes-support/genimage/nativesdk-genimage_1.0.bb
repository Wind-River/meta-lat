#
# Copyright (c) 2021 Wind River Systems, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
include genimage.inc

RDEPENDS:${PN} = " \
                  nativesdk-dnf \
                  nativesdk-rpm \
                  nativesdk-apt \
                  nativesdk-dpkg \
                  nativesdk-createrepo-c \
                  nativesdk-dosfstools \
                  nativesdk-syslinux \
                  nativesdk-mtools \
                  nativesdk-gptfdisk \
                  nativesdk-wic \
                  nativesdk-gnupg \
                  nativesdk-gnupg-gpg \
                  nativesdk-ostree \
                  nativesdk-python3-pyyaml \
                  nativesdk-shadow \
                  nativesdk-coreutils \
                  nativesdk-cpio \
                  nativesdk-gzip \
                  nativesdk-u-boot-mkimage \
                  nativesdk-pbzip2 \
                  nativesdk-bzip2 \
                  nativesdk-ca-certificates \
                  nativesdk-glib-networking \
                  nativesdk-kmod \
                  nativesdk-wget \
                  nativesdk-sloci-image \
                  nativesdk-umoci \
                  nativesdk-skopeo \
                  nativesdk-python3-texttable \
                  nativesdk-python3-argcomplete \
                  nativesdk-python3-pykwalify \
                  nativesdk-bmap-tools \
                  nativesdk-util-linux-uuidgen \
                  nativesdk-perl \
                  nativesdk-pigz \
                  nativesdk-debootstrap \
                  nativesdk-genisoimage \
                  nativesdk-syslinux-misc \
"

# Required by do_rootfs's intercept_scripts in sdk
RDEPENDS:${PN} += "nativesdk-gdk-pixbuf \
                   nativesdk-gtk+3 \
                   nativesdk-kmod \
                   nativesdk-nss \
"

SRC_URI += "\
           file://add_path.sh \
"

do_install:append() {
	mkdir -p ${D}${SDKPATHNATIVE}/environment-setup.d
	install -m 0755 ${WORKDIR}/add_path.sh ${D}${SDKPATHNATIVE}/environment-setup.d
	install -m 0755 ${WORKDIR}/bash_tab_completion.sh ${D}${SDKPATHNATIVE}/environment-setup.d
}

FILES:${PN} = "${SDKPATHNATIVE}"

EFI_SECURE_BOOT ?= "${@bb.utils.contains('DISTRO_FEATURES', 'efi-secure-boot', 'enable', 'disable', d)}"

python __anonymous () {
    override = d.getVar('OVERRIDE')
    machine = d.getVar('MACHINE')
    if machine in (d.getVar('OSTREE_SUPPORTED_ARM64_MACHINES') or "").split():
        d.appendVar('OVERRIDES', ':aarch64:{0}'.format(machine))
    elif machine in (d.getVar('OSTREE_SUPPORTED_ARM32_MACHINES') or "").split():
        d.appendVar('OVERRIDES', ':arm:{0}'.format(machine))
    elif machine == 'intel-x86-64' or machine == 'amd-snowyowl-64':
        d.appendVar('OVERRIDES', ':x86-64:{0}'.format(machine))

        if bb.utils.contains('DISTRO_FEATURES', 'efi-secure-boot', True, False, d) and \
           d.getVar('DEBIAN_CUSTOMIZE_FEED_URI') != 'not_set':
            d.setVar('BOOT_SINGED_SHIM', '$OECORE_TARGET_SYSROOT/boot/efi/EFI/BOOT/bootx64.efi')
            d.setVar('BOOT_SINGED_SHIMTOOL', '$OECORE_TARGET_SYSROOT/boot/efi/EFI/BOOT/mmx64.efi')
            d.setVar('BOOT_SINGED_GRUB', '$OECORE_TARGET_SYSROOT/boot/efi/EFI/BOOT/grubx64.efi')
            d.setVar('BOOT_EFITOOL', '$OECORE_TARGET_SYSROOT/boot/efi/EFI/BOOT/LockDown.efi')

        d.setVar('BOOT_NOSIG_GRUB', '$OECORE_TARGET_SYSROOT/boot/efi/EFI/BOOT/bootx64-nosig.efi')
        d.setVar('BOOT_GRUB_CFG', '$OECORE_TARGET_SYSROOT/boot/efi/EFI/BOOT/grub.cfg')

    d.setVar("DEFAULT_LOCAL_RPM_PACKAGE_FEED", "")
    d.setVar("DEFAULT_LOCAL_DEB_PACKAGE_FEED", "")
}

inherit features_check
REQUIRED_DISTRO_FEATURES = "ostree lat"

# this inherit needs to be the last one due to 'native-last' QA check
inherit nativesdk
