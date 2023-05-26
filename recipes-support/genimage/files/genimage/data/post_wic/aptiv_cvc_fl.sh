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
atf_s32="${DEPLOY_DIR_IMAGE}/atf-aptiv_cvc_fl.s32"
wicimage="$DEPLOY_DIR_IMAGE/${IMAGE_NAME}-${MACHINE}-${DATETIME}.rootfs.wic"
dd if=$atf_s32 of=$wicimage conv=notrunc seek=512 skip=512 oflag=seek_bytes iflag=skip_bytes
