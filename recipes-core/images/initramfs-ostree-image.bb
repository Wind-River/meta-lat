# Netboot initramfs image.
DESCRIPTION = "OSTree initramfs image"

OSTREE_INSTALLER ??= "1"

PACKAGE_INSTALL = " \
  ${@bb.utils.contains('OSTREE_INSTALLER', '1', 'initramfs-ostree-installer', '', d)} \
  initramfs-ostree-init \
  initramfs-ostree-console \
"

PACKAGE_EXCLUDE += "python"

# Do not pollute the initrd image with rootfs features
IMAGE_FEATURES = ""

NO_RECOMMENDATIONS = "1"

export IMAGE_BASENAME = "initramfs-ostree-image"
IMAGE_LINGUAS = ""

LICENSE = "MIT"

IMAGE_FSTYPES = "${INITRAMFS_FSTYPES} cpio.gz"

# Stop any kind of circular dependency with the flux-ota class
IMAGE_CLASSES:remove = "flux-ota"

IMAGE_CLASSES:remove = "fullmetalupdate_package_preinstalled_ostree"
IMAGE_CLASSES:remove = "fullmetalupdate_push_image_to_ostree"

inherit core-image image_types_ostree

IMAGE_ROOTFS_SIZE = "8192"
INITRAMFS_MAXSIZE ?= "262144"
# Users will often ask for extra space in their rootfs by setting this
# globally.  Since this is a initramfs, we don't want to make it bigger
IMAGE_ROOTFS_EXTRA_SPACE = "0"

BAD_RECOMMENDATIONS += "busybox-syslog"

PACKAGE_INSTALL:append = " \
	${@bb.utils.contains('DISTRO_FEATURES', 'luks', 'packagegroup-luks-initramfs', '', d)} \
	${@bb.utils.contains('DISTRO_FEATURES', 'ima', 'packagegroup-ima-initramfs', '', d)} \
"
ROOTFS_POSTPROCESS_COMMAND += "ostree_check_rpm_public_key;add_gpg_key;remove_boot_dir;"

remove_boot_dir() {
	# Remove any image files in the /boot directory
	rm -rf ${IMAGE_ROOTFS}/boot
}

add_gpg_key() {
	gpg_path="${GPG_PATH}"
	if [ -z "$gpg_path" ] ; then
		gpg_path="${TMPDIR}/.gnupg"
	fi
	if [ -n "${OSTREE_GPGID}" ] ; then
		FAIL=1
		if [ ${OSTREE_INSTALLER} = 1 -a -f $gpg_path/pubring.gpg ]; then
			cp $gpg_path/pubring.gpg ${IMAGE_ROOTFS}/usr/share/ostree/trusted.gpg.d/pubring.gpg
			FAIL=0
		fi
		if [ ${OSTREE_INSTALLER} = 1 -a -f $gpg_path/pubring.kbx ]; then
			cp $gpg_path/pubring.kbx ${IMAGE_ROOTFS}/usr/share/ostree/trusted.gpg.d/pubkbx.gpg
			FAIL=0
		fi
		if $FAIL = 1; then
			bb.fatal "Could not locate the public gpg signing key for OSTree"
		fi
	fi
}
