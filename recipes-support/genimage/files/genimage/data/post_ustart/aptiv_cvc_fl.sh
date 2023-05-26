#!/bin/bash
#
# Copyright (c) 2023 Wind River Systems, Inc.
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
atf_s32="${DEPLOY_DIR_IMAGE}/atf-aptiv_cvc_fl.s32"
dd if=$atf_s32 of=${USTART_SRC_IMAGE} conv=notrunc seek=512 skip=512 oflag=seek_bytes iflag=skip_bytes
pigz -f ${USTART_SRC_IMAGE}
