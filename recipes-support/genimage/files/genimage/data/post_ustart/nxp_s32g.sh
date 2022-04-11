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

USTART_SRC_GZIMAGE_LINK="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}.ustart.img.gz"
USTART_SRC_GZIMAGE="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${DATETIME}.ustart.img.gz"
USTART_SRC_IMAGE="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${DATETIME}.ustart.img"

remove_link() {
    f=$1
    [ ! -L $f ] && return
    real_f=`realpath ${f}`
    rm -rf $f $real_f
}


gunzip -f -k $USTART_SRC_GZIMAGE

j=0;
for plat in ${S32G_PLAT}; do
    j=$(expr $j + 1);
    type=`echo ${UBOOT_CONFIG} | awk -v "n=$j" '{print $n}'`;
    uimage="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${plat}-${DATETIME}.ustart.img"
    uzimage=${uimage}.gz
    uzimagelink="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${plat}.ustart.img.gz"
    cp ${USTART_SRC_IMAGE} ${uimage}
    if [ -n "${ATF_S32G_ENABLE}" -a -e ${DEPLOY_DIR_IMAGE}/atf-${type}.s32 ]; then
        dd if=${DEPLOY_DIR_IMAGE}/atf-${type}.s32 of=${uimage} conv=notrunc bs=256 count=1 seek=0;
        dd if=${DEPLOY_DIR_IMAGE}/atf-${type}.s32 of=${uimage} conv=notrunc bs=512 seek=1 skip=1;
    elif [ -e ${DEPLOY_DIR_IMAGE}/${UBOOT_BINARY}-${type} ]; then
        dd if=${DEPLOY_DIR_IMAGE}/${UBOOT_BINARY}-${type} of=${uimage} conv=notrunc bs=256 count=1 seek=0;
        dd if=${DEPLOY_DIR_IMAGE}/${UBOOT_BINARY}-${type} of=${uimage} conv=notrunc bs=512 seek=1 skip=1;
    fi;
    remove_link $uzimagelink
    pigz -f $uimage
    ln -snf -r $uzimage $uzimagelink
done;

rm -f ${USTART_SRC_IMAGE}
remove_link ${USTART_SRC_GZIMAGE_LINK}
