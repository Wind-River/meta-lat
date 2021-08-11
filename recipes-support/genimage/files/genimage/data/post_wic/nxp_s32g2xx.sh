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
USTART_SRC_IMAGE_LINK="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}.wic"
USTART_SRC_IMAGE="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${DATETIME}.rootfs.wic"
USTART_EVB_IMAGE="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-evb-${DATETIME}.rootfs.wic"
USTART_RDB2_IMAGE="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-rdb2-${DATETIME}.rootfs.wic"
USTART_EVB_IMAGE_LINK="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-evb.wic"
USTART_RDB2_IMAGE_LINK="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-rdb2.wic"

remove_link() {
    f=$1
    [ ! -L $f ] && return
    real_f=`realpath ${f}`
    rm -rf $f $real_f
}

cp ${USTART_SRC_IMAGE} ${USTART_EVB_IMAGE}
dd if=$DEPLOY_DIR_IMAGE/u-boot.s32-s32g274aevb of=${USTART_EVB_IMAGE} conv=notrunc bs=256 count=1 seek=0;
dd if=$DEPLOY_DIR_IMAGE/u-boot.s32-s32g274aevb of=${USTART_EVB_IMAGE} conv=notrunc bs=512 seek=1 skip=1;
remove_link $USTART_EVB_IMAGE_LINK
ln -snf -r ${USTART_EVB_IMAGE} ${USTART_EVB_IMAGE_LINK}

if [ -e $DEPLOY_DIR_IMAGE/u-boot.s32-s32g274ardb2 ]; then
    cp ${USTART_SRC_IMAGE} ${USTART_RDB2_IMAGE}
    if [ -n "${ATF_S32G_ENABLE}" ]; then
        dd if=${ATF_IMAGE_FILE} of=${USTART_RDB2_IMAGE} conv=notrunc bs=256 count=1 seek=0;
        dd if=${ATF_IMAGE_FILE} of=${USTART_RDB2_IMAGE} conv=notrunc bs=512 seek=1 skip=1;
    else
        dd if=$DEPLOY_DIR_IMAGE/u-boot.s32-s32g274ardb2 of=${USTART_RDB2_IMAGE} conv=notrunc bs=256 count=1 seek=0;
        dd if=$DEPLOY_DIR_IMAGE/u-boot.s32-s32g274ardb2 of=${USTART_RDB2_IMAGE} conv=notrunc bs=512 seek=1 skip=1;
    fi;
    remove_link $USTART_RDB2_IMAGE_LINK
    ln -snf -r ${USTART_RDB2_IMAGE} ${USTART_RDB2_IMAGE_LINK}
fi

remove_link ${USTART_SRC_IMAGE_LINK}
