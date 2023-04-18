#
# Copyright (C) 2021 Wind River Systems, Inc.
#
# Deploy appsdk to SDK
#
# Implementation of Full Image generator with Application SDK
TOOLCHAIN_HOST_TASK:append = " \
    nativesdk-wic \
    nativesdk-genimage \
    nativesdk-bootfs \
    nativesdk-appsdk \
"
TOOLCHAIN_TARGET_TASK:append = " \
    qemuwrapper-cross \
"

TOOLCHAIN_TARGET_TASK:append:x86-64 = " \
    syslinux-misc \
    syslinux-isolinux \
    syslinux-pxelinux \
    ${@bb.utils.contains('DISTRO_FEATURES', 'efi-secure-boot', 'grub-efi', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'efi-secure-boot', 'shim', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'efi-secure-boot', 'efitools', '', d)} \
"

POPULATE_SDK_PRE_TARGET_COMMAND += "copy_pkgdata_to_sdk;"
copy_pkgdata_to_sdk() {
    copy_pkgdata ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/pkgdata
}

copy_pkgdata() {
    dest=$1
    install -d $dest
    tar cfj $dest/pkgdata.tar.bz2 -C ${TMPDIR}/pkgdata ${MACHINE}
    (
        cd $dest;
        sha256sum pkgdata.tar.bz2 > pkgdata.tar.bz2.sha256sum
    )
}

POPULATE_SDK_PRE_TARGET_COMMAND += "copy_ostree_initramfs_to_sdk;"

# The copy_ostree_initramfs_to_sdk requires {INITRAMFS_IMAGE}-${MACHINE}.${INITRAMFS_FSTYPES}
do_populate_sdk[depends] += "${INITRAMFS_IMAGE}:do_image_complete"

copy_ostree_initramfs_to_sdk() {
    install -d ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/genimage/data/initramfs
    if [ -L ${DEPLOY_DIR_IMAGE}/${INITRAMFS_IMAGE}-${MACHINE}.${INITRAMFS_FSTYPES} ];then
        cp -f ${DEPLOY_DIR_IMAGE}/${INITRAMFS_IMAGE}-${MACHINE}.${INITRAMFS_FSTYPES} \
            ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/genimage/data/initramfs/
    fi
}

IMAGE_CLASSES += "qemuboot"
do_populate_sdk:prepend() {
    localdata = bb.data.createCopy(d)
    if localdata.getVar('MACHINE') == 'bcm-2xxx-rpi4':
        localdata.appendVar('QB_OPT_APPEND', ' -bios @DEPLOYDIR@/qemu-u-boot-bcm-2xxx-rpi4.bin')
    localdata.setVar('QB_MEM', '-m 1024')

    if localdata.getVar('MACHINE') in ['bcm-2xxx-rpi4', 'intel-x86-64']:
        bb.build.exec_func('do_write_qemuboot_conf', localdata)
}

POPULATE_SDK_PRE_TARGET_COMMAND += "copy_qemu_data;"
copy_qemu_data() {
    install -d ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/qemu_data
    if [ -e ${DEPLOY_DIR_IMAGE}/qemu-u-boot-bcm-2xxx-rpi4.bin ]; then
        cp -f ${DEPLOY_DIR_IMAGE}/qemu-u-boot-bcm-2xxx-rpi4.bin ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/qemu_data/
    fi
    if [ -e ${DEPLOY_DIR_IMAGE}/ovmf.qcow2 ]; then
        cp -f ${DEPLOY_DIR_IMAGE}/ovmf.qcow2 ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/qemu_data/
    fi
    if [ -e ${DEPLOY_DIR_IMAGE}/ovmf.vars.qcow2 ]; then
        cp -f ${DEPLOY_DIR_IMAGE}/ovmf.vars.qcow2 ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/qemu_data/
    fi
    if [ -e ${DEPLOY_DIR_IMAGE}/ovmf.secboot.qcow2 ]; then
        cp -f ${DEPLOY_DIR_IMAGE}/ovmf.secboot.qcow2 ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/qemu_data/
    fi

    qemuboot_conf="${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.qemuboot.conf"
    if [ -e $qemuboot_conf ]; then
        sed -e '/^staging_bindir_native =/d' \
            -e '/^staging_dir_host =/d' \
            -e '/^staging_dir_native = /d' \
            -e '/^kernel_imagetype =/d' \
            -e 's/^deploy_dir_image =.*$/deploy_dir_image = @DEPLOYDIR@/' \
            -e 's/^image_link_name =.*$/image_link_name = @IMAGE_LINK_NAME@/' \
            -e 's/^image_name =.*$/image_name = @IMAGE_NAME@/' \
            -e 's/^qb_mem =.*$/qb_mem = -m @MEM@/' \
            -e 's/^qb_default_fstype =.*$/qb_default_fstype = wic/' \
                $qemuboot_conf > \
                    ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/qemu_data/qemuboot.conf.in
    fi
}

POPULATE_SDK_PRE_TARGET_COMMAND += "copy_bootfile;"
copy_bootfile() {
	if [ -n "${BOOTFILES_DIR_NAME}" -a -d "${DEPLOY_DIR_IMAGE}/${BOOTFILES_DIR_NAME}" ]; then
		install -d ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/bootfiles
		cp -rf ${DEPLOY_DIR_IMAGE}/${BOOTFILES_DIR_NAME} ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/bootfiles/
	fi

	for f in ${BOOTFILES}; do
		install -d ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/bootfiles
		if [ -e "${DEPLOY_DIR_IMAGE}/$f" ]; then
			cp -f ${DEPLOY_DIR_IMAGE}/$f ${SDK_OUTPUT}${SDKPATHNATIVE}${datadir}/bootfiles/
		fi
	done
}

# Make sure code changes can result in rebuild
do_populate_sdk[vardeps] += "extract_pkgdata_postinst"
SDK_POST_INSTALL_COMMAND += "${extract_pkgdata_postinst}"
extract_pkgdata_postinst() {
    cd $target_sdk_dir/sysroots/${SDK_SYS}${datadir}/pkgdata/;
    mkdir $target_sdk_dir/sysroots/pkgdata;
    tar xf pkgdata.tar.bz2 -C $target_sdk_dir/sysroots/pkgdata;
}

# Make sure the existence of Yocto var file in pkgdata
do_populate_sdk[depends] += "initramfs-ostree:do_export_yocto_vars"

python __anonymous () {
    machine = d.getVar('MACHINE')
    if machine == 'intel-socfpga-64':
        d.appendVarFlag('do_populate_sdk', 'depends', ' s10-u-boot-scr:do_deploy')
        d.appendVarFlag('do_populate_sdk', 'depends', ' u-boot-socfpga:do_deploy')
}
