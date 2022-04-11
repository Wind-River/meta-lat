#!/bin/bash
#
# Copyright (c) 2021 Wind River Systems, Inc.
#
# SPDX-License-Identifier:  GPL-2.0
#
set -x
set -e
## Require environments
# DEPLOY_DIR_IMAGE
# IMAGE_NAME
# DATETIME
# MACHINE
S32G_PLAT="rdb2 evb rdb3"
UBOOT_CONFIG="s32g274ardb2 s32g2xxaevb s32g399ardb3"
UBOOT_BINARY="u-boot-s32.bin"

USTART_SRC_IMAGE_LINK="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}.wic"
USTART_SRC_IMAGE="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${DATETIME}.rootfs.wic"

remove_link() {
    f=$1
    [ ! -L $f ] && return
    real_f=`realpath ${f}`
    rm -rf $f $real_f
}

j=0
for plat in ${S32G_PLAT}; do
    j=$(expr $j + 1);
    type=`echo ${UBOOT_CONFIG} | awk -v "n=$j" '{print $n}'`
    wicimage="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${plat}-${DATETIME}.rootfs.wic"
    wicimagelink="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${plat}.wic"
    cp ${USTART_SRC_IMAGE} ${wicimage}
    if [ -n "${ATF_S32G_ENABLE}" -a -e ${DEPLOY_DIR_IMAGE}/atf-${type}.s32 ]; then
        dd if=${DEPLOY_DIR_IMAGE}/atf-${type}.s32 of=${wicimage} conv=notrunc bs=256 count=1 seek=0
        dd if=${DEPLOY_DIR_IMAGE}/atf-${type}.s32 of=${wicimage} conv=notrunc bs=512 seek=1 skip=1
    elif [ -e ${DEPLOY_DIR_IMAGE}/${UBOOT_BINARY}-${type} ]; then
        dd if=${DEPLOY_DIR_IMAGE}/${UBOOT_BINARY}-${type} of=${wicimage} conv=notrunc bs=256 count=1 seek=0
        dd if=${DEPLOY_DIR_IMAGE}/${UBOOT_BINARY}-${type} of=${wicimage} conv=notrunc bs=512 seek=1 skip=1
    fi
    remove_link $wicimagelink
    ln -snf -r $wicimage $wicimagelink
done

remove_link ${USTART_SRC_IMAGE_LINK}
