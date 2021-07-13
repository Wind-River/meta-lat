SUMMARY = "Basic init for initramfs to mount ostree and pivot root"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"
SRC_URI = "file://init-ostree.sh \
	file://init-ostree-install.sh \
	file://init.luks-ostree \
"

PR = "r9"

OSTREE_ALLOW_RM_VAR ??= ""

RDEPENDS_${PN} = "util-linux-sfdisk gptfdisk e2fsprogs-mke2fs"

do_configure() {
}

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
}

# While this package maybe an allarch due to it being a 
# simple script, reality is that it is Host specific based
# on the COMPATIBLE_HOST below, which needs to take precedence
#inherit allarch
INHIBIT_DEFAULT_DEPS = "1"

FILES_${PN} = " /init /init.luks-ostree /dev /install"

COMPATIBLE_HOST = "(arm|aarch64|i.86|x86_64|powerpc).*-linux"
