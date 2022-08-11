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
UBOOT_CONFIG="s32g274ardb2 s32g2xxaevb s32g399ardb3 s32g3xxaevb"
UBOOT_BINARY="u-boot-s32.bin"

USTART_SRC_IMAGE_LINK="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}.wic"
USTART_SRC_IMAGE="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${DATETIME}.rootfs.wic"

remove_link() {
    f=$1
    [ ! -L $f ] && return
    real_f=`realpath ${f}`
    rm -rf $f $real_f
}

for plat in ${UBOOT_CONFIG}; do
    atf_s32="${DEPLOY_DIR_IMAGE}/atf-$plat.s32"
    ofname="${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-${plat}-${DATETIME}.rootfs.wic"
    cp $USTART_SRC_IMAGE $ofname
    if [ "$plat" = "s32g2xxaevb" ] && [ "${HSE_SEC_ENABLED}" = "1" ]; then
        dd if=$atf_s32 of=$ofname bs=512 seek=1 skip=1 conv=notrunc,fsync
        dd if=$atf_s32.signature of=$ofname  bs=512 seek=9 conv=notrunc,fsync
    else
        dd if=$atf_s32 of=$ofname conv=notrunc bs=256 count=1 seek=0
        dd if=$atf_s32 of=$ofname conv=notrunc bs=512 seek=1 skip=1
    fi
    if [ $plat = "s32g3xxaevb" ]; then
        plat="evb3"
    elif [ $plat = "s32g2xxaevb" ]; then
        plat="evb"
    else
        plat="$(echo $plat | grep -o '....$')"
    fi
    linkname="${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}-${MACHINE}-$plat.wic"
    ln -sf $ofname $linkname
done
remove_link ${USTART_SRC_IMAGE_LINK}
