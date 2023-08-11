FILESEXTRAPATHS:prepend := "${THISDIR}:${THISDIR}/files:"

SRC_URI += " \
    file://0001-fsck-Throw-and-error-and-return-non-zero-for-non-ver.patch \
    file://0002-u-boot-add-bootdir-to-the-generated-uEnv.txt.patch \
    file://0003-tweak-regex-of-ostree-system-generator.patch \
    file://0004-deploy-using-etc-in-runtime-as-merge-source.patch \
    file://0005-create-links-to-the-deploy-directory-in-boot-and-ost.patch \
    file://0006-Allow-updating-files-in-the-boot-directory.patch \
    file://0007-get-output-of-ostree-prepare-root-back.patch \
    file://0008-no-warn-if-we-find-content-in-the-deployment-s-var.patch \
    file://0009-support-no-initramfs-situation.patch \
    file://system-export.sh \
    file://init-ostree-no-initramfs.sh \
"
SRC_URI:append:x86-64 = " \
    file://0001-deploy-Handle-a-read-only-boot-efi.patch \
"

RDEPENDS:${PN}:class-target += " \
    pv \
    ${@bb.utils.contains('DISTRO_FEATURES', 'ostree-no-initramfs', '${PN}-init-no-initramfs', '', d)} \
"

RDEPENDS:${PN}-init-no-initramfs = " \
    tar \
    util-linux-blkid \
    util-linux-fdisk \
    util-linux-lsblk \
    util-linux-sfdisk \
    util-linux-blockdev \
    util-linux-mount \
    e2fsprogs \
    e2fsprogs-resize2fs \
    e2fsprogs-mke2fs \
    e2fsprogs-e2fsck \
"

PACKAGES =+ "${PN}-init-no-initramfs"

FILES:${PN}-init-no-initramfs = " \
    /init-ostree-pre.sh \
"

# Use the given compiler to build ostree-prepare-root statically linked
PACKAGECONFIG[static-ostree-prepare-root] = "--with-static-compiler='${CC}', --without-static-compiler"

PACKAGECONFIG:append = " \
    builtin-grub2-mkconfig \
    ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'systemd libmount', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'ostree-no-initramfs', 'static-ostree-prepare-root', '', d)} \
"

do_install:append:class-target() {
	install -d ${D}/${bindir}
	install -m 0755 ${WORKDIR}/system-export.sh ${D}/${bindir}/system-export
	install -m 0755 ${WORKDIR}/init-ostree-no-initramfs.sh ${D}/init-ostree-pre.sh
}
