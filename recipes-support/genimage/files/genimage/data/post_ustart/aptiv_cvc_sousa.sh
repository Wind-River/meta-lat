#!/bin/bash
#
# Copyright (c) 2022 Wind River Systems, Inc.
#
# SPDX-License-Identifier:  GPL-2.0-only
#
set -x
set -e
## Require environments
# DEPLOY_DIR_IMAGE
# IMAGE_NAME
# DATETIME
# MACHINE
USTART_SRC_GZIMAGE="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${DATETIME}.ustart.img.gz"
USTART_SRC_IMAGE="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${DATETIME}.ustart.img"

gunzip -f $USTART_SRC_GZIMAGE
atf_s32="${DEPLOY_DIR_IMAGE}/atf-aptiv_cvc_sousa.s32"
# In order to not override partition table of image, do not write starting
# 256~512 byte, only write atf from starting 0~256 byte, 512~end byte
# to image
dd if=$atf_s32 of=${USTART_SRC_IMAGE} conv=notrunc bs=256 count=1 seek=0;
dd if=$atf_s32 of=${USTART_SRC_IMAGE} conv=notrunc bs=512 seek=1 skip=1;
pigz -f ${USTART_SRC_IMAGE}
