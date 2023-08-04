SUMMARY = "Basic init for initramfs to mount ostree and pivot root"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"
SRC_URI = "file://init-ostree.sh \
	file://init-ostree-install.sh \
	file://init.luks-ostree \
	file://lat-installer.sh \
	file://lat-installer.hook \
"

PR = "r9"

OSTREE_ALLOW_RM_VAR ??= ""

INITRAMFS_FEATURES ??= "busybox"
PkgsBusyBox = "busybox busybox-udhcpc"
PkgsCoreUtils = "coreutils \
    dhcp-client \
    util-linux \
    util-linux-umount \
    util-linux-mount \
    util-linux-setsid \
    iproute2 \
"
INITRAMFS_PKGS = "${@bb.utils.contains('INITRAMFS_FEATURES', 'busybox', "${PkgsBusyBox}", "${PkgsCoreUtils}", d)}"
INITRAMFS_PKGS:append:x86-64 = " \
    grub \
    efibootmgr \
    ${@bb.utils.contains('DISTRO_FEATURES', 'luks ostree', 'grub-efi-boot-key', '', d)} \
"

RDEPENDS:${PN} = " \
    ${PN}-installer \
    ${PN}-init \
    ${PN}-console \
"
RDEPENDS:${PN}-installer = " \
    killall \
    init-ifupdown \
    ifupdown \
    debianutils-run-parts \
    iproute2-ip \
    kmod \
    bzip2 \
    gnupg \
    kbd \
    util-linux-blkid \
    util-linux-lsblk \
    util-linux-fsck \
    util-linux-blockdev \
    dosfstools \
    curl \
    udev \
    mdadm \
    base-passwd \
    rng-tools \
    e2fsprogs-tune2fs \
    e2fsprogs-e2fsck \
    eject \
    pv \
    mttyexec \
    gzip \
    findutils \
    grep \
    sed \
    gawk \
    glib-networking \
    ca-certificates \
    util-linux-sfdisk \
    gptfdisk \
    e2fsprogs-mke2fs \
    bash \
    ostree \
    ${INITRAMFS_PKGS} \
"
RDEPENDS:${PN}-init = " \
    udev \
    busybox \
    tar \
    util-linux-blkid \
    util-linux-fdisk \
    util-linux-lsblk \
    util-linux-sfdisk \
    util-linux-blockdev \
    e2fsprogs \
    e2fsprogs-resize2fs \
    e2fsprogs-mke2fs \
    ostree-switchroot \
"

do_configure() {
}

ALLOW_EMPTY:${PN} = "1"
PACKAGES = "${PN}-installer ${PN}-init ${PN}-console ${PN}"

FILES:${PN}-installer = " \
    /install \
    /lat-installer.sh \
    /lat-installer.hook \
"
FILES:${PN}-init = " \
    /init \
    /init.luks-ostree \
"
FILES:${PN}-console = " \
    /dev/console \
"

do_install() {
	install -m 0755 ${WORKDIR}/init-ostree-install.sh ${D}/install
	sed -i -e 's#@OSTREE_OSNAME@#${OSTREE_OSNAME}#g' ${D}/install
	if [ "${OSTREE_FDISK_BLM}" != "" ] ; then
		sed -i -e 's/^BLM=.*/BLM=${OSTREE_FDISK_BLM}/' ${D}/install
	fi
	if [ "${OSTREE_FDISK_FSZ}" != "" ] ; then
		sed -i -e 's/^FSZ=.*/FSZ=${OSTREE_FDISK_FSZ}/' ${D}/install
	fi
	if [ "${OSTREE_FDISK_BSZ}" != "" ] ; then
		sed -i -e 's/^BSZ=.*/BSZ=${OSTREE_FDISK_BSZ}/' ${D}/install
	fi
	if [ "${OSTREE_FDISK_RSZ}" != "" ] ; then
		sed -i -e 's/^RSZ=.*/RSZ=${OSTREE_FDISK_RSZ}/' ${D}/install
	fi
        install -m 0755 ${WORKDIR}/init-ostree.sh ${D}/init
	if [ "${OSTREE_FDISK_VSZ}" != "" ] ; then
		sed -i -e 's/^VSZ=.*/VSZ=${OSTREE_FDISK_VSZ}/' ${D}/install
		sed -i -e 's/^VSZ=.*/VSZ=${OSTREE_FDISK_VSZ}/' ${D}/init
	fi
	if [ "${OSTREE_ALLOW_RM_VAR}" != "" ] ; then
		sed -i -e 's/^ALLOW_RM_VAR=.*/ALLOW_RM_VAR=${OSTREE_ALLOW_RM_VAR}/' ${D}/init
	fi
	install -m 0755 ${WORKDIR}/init.luks-ostree ${D}/init.luks-ostree
	sed -i -e 's#@OSTREE_OSNAME@#${OSTREE_OSNAME}#g' ${D}/init.luks-ostree
	# Create device nodes expected by some kernels in initramfs
	# before even executing /init.
	install -d ${D}/dev
	mknod -m 622 ${D}/dev/console c 5 1
	install -m 0755 ${WORKDIR}/lat-installer.sh ${D}/lat-installer.sh
	install -m 0755 ${WORKDIR}/lat-installer.hook ${D}/lat-installer.hook
}

# While this package maybe an allarch due to it being a 
# simple script, reality is that it is Host specific based
# on the COMPATIBLE_HOST below, which needs to take precedence
#inherit allarch
INHIBIT_DEFAULT_DEPS = "1"

FILES:${PN} = " /init /init.luks-ostree /dev /install /lat-installer.sh /lat-installer.hook"

COMPATIBLE_HOST = "(arm|aarch64|i.86|x86_64|powerpc).*-linux"

# For LAT usage
do_export_yocto_vars() {
    mkdir -p ${PKGDATA_DIR}
    echo "[yocto]" > ${PKGDATA_DIR}/.yocto_vars.env
    echo "MULTIMACH_TARGET_SYS=${MULTIMACH_TARGET_SYS}" >> ${PKGDATA_DIR}/.yocto_vars.env
    echo "PACKAGE_ARCHS=${PACKAGE_ARCHS}" >> ${PKGDATA_DIR}/.yocto_vars.env
}
addtask export_yocto_vars
