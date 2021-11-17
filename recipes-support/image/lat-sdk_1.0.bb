#
# Copyright (C) 2021 Wind River Systems, Inc.
#
DESCRIPTION = "Provides image to generate AppSDK for Wind River Linux Assembly Tool."

LICENSE = "MIT"

NO_RECOMMENDATIONS = "1"

SDKIMAGE_LINGUAS = ""
TOOLCHAIN_OUTPUTNAME = "${SDK_NAME}-${SDK_VERSION}"
SDK_NAME = "${BPN}-${DISTRO}-${MACHINE}"
SDK_VERSION = "${PV}"

do_populate_sdk:prepend() {
    d.setVar('PACKAGE_INSTALL', 'packagegroup-base')
}

IMAGE_INSTALL = "\
    base-files \
    base-passwd \
    ${VIRTUAL-RUNTIME_update-alternatives} \
    openssh \
    ca-certificates \
    packagegroup-base \
    "

# Only need tar.bz2 for container image
IMAGE_FSTYPES:remove = " \
    live wic wic.bmap ostreepush otaimg \
"

python () {
    machine = d.getVar('MACHINE')
    if machine == 'intel-x86-64':
        d.appendVarFlag('do_populate_sdk', 'depends', ' ovmf:do_deploy')
    elif machine == 'bcm-2xxx-rpi4':
        d.appendVarFlag('do_populate_sdk', 'depends', ' rpi-bootfiles:do_deploy u-boot:do_deploy')
}

IMAGE_FEATURES += "package-management"

inherit core-image features_check populate_sdk
REQUIRED_DISTRO_FEATURES = "ostree lat"

# Make sure the existence of ostree initramfs image
do_populate_sdk[depends] += "initramfs-ostree-image:do_image_complete"

deltask do_populate_sdk_ext
